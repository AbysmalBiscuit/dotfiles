export const meta = {
  name: 'batch-issue-setup',
  description: 'Set up worktrees for multiple Linear issues; bug issues get parallel Sentry/Vercel/PostHog recon',
  whenToUse: 'When the user pastes multiple Linear issue IDs or URLs to bootstrap together',
  phases: [
    { title: 'Classify', detail: 'fetch each Linear issue, triage bug vs non-bug' },
    { title: 'Setup', detail: 'run the /issue-setup flow per issue (git ops serialized)' },
    { title: 'Recon', detail: 'Sentry/Vercel/PostHog subagents per bug issue' },
    { title: 'Correlate', detail: 'merge recon into each bug summary' },
  ],
}

let input = args
if (typeof input === 'string') {
  try { input = JSON.parse(input) } catch { input = input.split(/[\s,]+/) }
}
const rawInput = Array.isArray(input) ? input : (input && input.issues) || []
const dryRun = !Array.isArray(input) && !!(input && input.dryRun)
const issues = rawInput.map(s => String(s).trim()).filter(Boolean)
if (issues.length === 0) {
  throw new Error('No issues passed. Invoke with args: {issues: ["ENG-1234", ...], dryRun?: bool} or a plain array.')
}
log(`${issues.length} issue(s) to set up${dryRun ? ' [DRY RUN]' : ''}`)

const CLASSIFY_SCHEMA = {
  type: 'object',
  required: ['issueId', 'title', 'url', 'isBug', 'reason'],
  properties: {
    issueId: { type: 'string', description: 'Canonical identifier, e.g. ENG-1234' },
    title: { type: 'string' },
    url: { type: 'string' },
    state: { type: 'string' },
    labels: { type: 'array', items: { type: 'string' } },
    isBug: { type: 'boolean' },
    reason: { type: 'string', description: 'One sentence naming the signal(s) the verdict keyed on' },
    errorSignature: {
      type: 'object',
      description: 'Only when isBug; "unknown" for fields the issue does not state',
      properties: {
        message: { type: 'string' },
        stackFrame: { type: 'string' },
        entryPoint: { type: 'string' },
        timeWindow: { type: 'string' },
        environment: { type: 'string' },
        app: { type: 'string' },
      },
    },
  },
}

const SETUP_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status: { type: 'string', enum: ['ok', 'blocked', 'failed'] },
    worktree: { type: 'string' },
    branch: { type: 'string' },
    ports: { type: 'object' },
    apps: { type: 'array', items: { type: 'string' } },
    summaryPath: { type: 'string' },
    sentry: {
      type: 'object',
      properties: { url: { type: 'string' }, shortId: { type: 'string' } },
    },
    notes: { type: 'string', description: 'Blockers, ambiguities, unassigned Sentry candidates' },
  },
}

const RECON_SCHEMA = {
  type: 'object',
  required: ['found', 'report'],
  properties: {
    found: { type: 'boolean', description: 'false when the source has nothing on this error' },
    report: { type: 'string', description: 'Compact structured findings, not a log dump' },
  },
}

const CORRELATE_SCHEMA = {
  type: 'object',
  required: ['hypothesis', 'confidence', 'appended'],
  properties: {
    hypothesis: { type: 'string' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    falsifyingExperiment: { type: 'string' },
    appended: { type: 'boolean', description: 'true once the summary file was extended' },
  },
}

function classifyPrompt(raw) {
  return `Triage Linear issue "${raw}" for batch worktree setup. Read-only: fetch and classify, change nothing.

1. Parse the issue identifier (ABC-123 form) from the input; if it is a linear.app URL, extract the identifier from it.
2. Load the Linear tools via ToolSearch ("select:mcp__linear__get_issue,mcp__linear__list_comments") and fetch the issue and its comments.
3. isBug = true when at least one of these observable signals is present:
   - a label named Bug, Error, Defect, or Regression (case-insensitive), or the issue was created from Sentry;
   - the description or comments contain an error message, exception type, stack trace, HTTP 4xx/5xx status, or a sentry.io link;
   - the description reports previously-working behavior now failing ("crashes", "broken", "no longer works", "fails with");
   - the description reports incorrect output reaching users without any error being thrown: wrong values, wrong calculation, hardcoded/placeholder data on a production path, data shown to the wrong user.
   Feature requests, refactors, chores, migration-sweep tasks, and docs are isBug = false. When none of the signals above is present, isBug = false.
4. When isBug, extract the error signature: message (error message / exception type), stackFrame (file:function if named), entryPoint (route / endpoint / UI action / job), timeWindow (first report to now, from issue timestamps), environment (prod | preview | staging), app (affected app). Write "unknown" for fields the issue does not state.

reason = one sentence naming the exact signal(s) the verdict keyed on.`
}

function setupPrompt(c) {
  const dry = dryRun
    ? `DRY RUN: pass --dry-run to \`issue setup\`; do not create a worktree, do not assign Sentry issues, do not comment on Linear, do not write a summary file. Report the would-be branch/worktree/ports.`
    : `Run it for real.`
  return `Set up a worktree for Linear issue ${c.issueId} ("${c.title}").

Read /home/lev/.claude/commands/issue-setup.md and execute its steps for this issue. Batch-mode adjustments — you are one of several concurrent setup agents and there is no user to ask:
- Never prompt the user. Where the command says to ask:
  - multiple plausible Sentry candidates -> assign none; list the candidate URLs in the summary's Sentry line and in notes;
  - "branch already exists" -> do not force or reuse; return status "blocked" with the branch name in notes.
- Skip the command's step 6 (report back) — return the same data via StructuredOutput instead.
- ${dry}
- If \`issue setup\` or an MCP call fails, return status "failed" with the exact error in notes rather than retrying blind.

status "ok" requires: worktree created (or dry-run previewed), summary file written (skip in dry run), and the JSON from \`issue setup\` parsed into worktree/branch/ports.`
}

function reconContext(c) {
  const sig = c.errorSignature || {}
  return `Error signature for ${c.issueId} ("${c.title}", ${c.url}):
- message: ${sig.message || 'unknown'}
- stack frame: ${sig.stackFrame || 'unknown'}
- entry point: ${sig.entryPoint || 'unknown'}
- time window: ${sig.timeWindow || 'unknown'}
- environment: ${sig.environment || 'unknown'}
- app: ${sig.app || 'unknown'}

You are READ-ONLY: never resolve, assign, redeploy, or mutate anything.
If your source has nothing on this error, return found=false and say so plainly — do not pad with plausible-sounding findings. Return a compact structured report, not a log dump.`
}

function sentryPrompt(c) {
  return `Sentry recon — what threw.

${reconContext(c)}

Load Sentry tools via ToolSearch ("select:mcp__plugin_sentry_sentry__find_projects,mcp__plugin_sentry_sentry__search_issues,mcp__plugin_sentry_sentry__search_events,mcp__plugin_sentry_sentry__get_sentry_resource"). Narrow to the right project with find_projects, then search_issues on the error message / exception type, scoped to the environment. On the best match pull the stack trace, culprit, firstSeen/lastSeen, release, event count, users affected.

report must contain: issue URL + short ID, exact firstSeen timestamp, the release it appeared in, frequency and user count, and the top 3 APPLICATION stack frames (skip vendor/node_modules frames).`
}

function vercelPrompt(c) {
  return `Vercel recon — what shipped.

${reconContext(c)}

There is no Vercel MCP; shell out to the \`vercel\` CLI (vercel ls <project>, vercel inspect <deployment-url>, vercel logs <deployment-url>). If the CLI is not authenticated, return found=false reporting that — do not guess.

report must contain: deployments landing inside the time window, each with timestamp, commit sha, author, PR; any build/runtime errors; and the deploy immediately preceding the error's first occurrence — the prime suspect.`
}

function posthogPrompt(c) {
  return `PostHog recon — who hit it.

${reconContext(c)}

Load the PostHog tool via ToolSearch ("select:mcp__plugin_posthog_posthog__exec") for HogQL over the events table plus the error-tracking / session-replay surfaces.

report must contain: how many distinct users hit it and whether they cluster (one org? one browser? one plan tier?); any feature flag enabled for affected users but not unaffected ones; session replay links for 1-2 representative failures; and whether the event volume started abruptly (deploy) or ramped (rollout).`
}

function correlatePrompt(c, s, recon) {
  return `Correlate bug recon for ${c.issueId} and extend its session summary.

${reconContext(c)}

Recon reports:
--- SENTRY (found=${recon.sentry ? recon.sentry.found : 'agent failed'}) ---
${recon.sentry ? recon.sentry.report : 'recon agent did not return'}
--- VERCEL (found=${recon.vercel ? recon.vercel.found : 'agent failed'}) ---
${recon.vercel ? recon.vercel.report : 'recon agent did not return'}
--- POSTHOG (found=${recon.posthog ? recon.posthog.found : 'agent failed'}) ---
${recon.posthog ? recon.posthog.report : 'recon agent did not return'}

Line the findings up against the time window:
- Sentry firstSeen just after a Vercel deploy -> that commit is the prime suspect.
- Tracks a PostHog feature-flag rollout curve instead -> the flag gates the broken path; the code may have shipped earlier and lain dormant.
- Correlates with neither -> suspect data, not code: a migration, upstream API change, expired credential. Say so and say what to check next.

Append to the summary file at ${s.summaryPath} two sections:

## Bug recon
- **Error:** / **Entry point:** / **Environment:** / **Sentry:** {URL, short ID, firstSeen, release, N events / M users} / **Suspect deploy:** {sha + PR + timestamp, or "none — see below"} / **Feature flag:** / **Blast radius:** / **Replays:**
Write "none found" for anything a source genuinely had nothing on — an empty field is a finding; a fabricated one poisons the next session.

## Leading hypothesis
{one paragraph} — confidence: {low | medium | high}
Cheapest falsifying experiment: {what to run}
Note: call-path tracing (/graphify) and git archaeology were deferred to the worktree session — run /issue-start there.

Then in "Suggested first steps", if not already present, note that recon ran and the hypothesis above is the starting point.`
}

// issue setup does git fetch + worktree add on the shared repo; concurrent runs
// race on the git lock, so setup calls are chained while everything else fans out.
let gitChain = Promise.resolve()
function serialized(fn) {
  const run = gitChain.then(fn, fn)
  gitChain = run.then(() => undefined, () => undefined)
  return run
}

const results = await pipeline(
  issues,
  raw => agent(classifyPrompt(raw), {
    label: `classify:${raw.replace(/^.*\//, '').slice(0, 24)}`,
    phase: 'Classify',
    schema: CLASSIFY_SCHEMA,
  }),
  c => {
    if (!c) return null
    log(`${c.issueId}: ${c.isBug ? 'BUG' : 'non-bug'} — ${c.reason}`)
    return serialized(() => agent(setupPrompt(c), {
      label: `setup:${c.issueId}`,
      phase: 'Setup',
      schema: SETUP_SCHEMA,
    })).then(s => ({ c, s }))
  },
  async (r) => {
    if (!r || !r.s) return r
    const { c, s } = r
    if (!c.isBug) return { ...r, recon: null, correlation: null }
    if (s.status !== 'ok') {
      log(`${c.issueId}: setup ${s.status} — skipping recon`)
      return { ...r, recon: null, correlation: null }
    }
    if (dryRun) {
      log(`${c.issueId}: dry run — recon skipped`)
      return { ...r, recon: null, correlation: null }
    }
    const [sentry, vercel, posthog] = await parallel([
      () => agent(sentryPrompt(c), { label: `sentry:${c.issueId}`, phase: 'Recon', schema: RECON_SCHEMA }),
      () => agent(vercelPrompt(c), { label: `vercel:${c.issueId}`, phase: 'Recon', schema: RECON_SCHEMA }),
      () => agent(posthogPrompt(c), { label: `posthog:${c.issueId}`, phase: 'Recon', schema: RECON_SCHEMA }),
    ])
    const correlation = await agent(correlatePrompt(c, s, { sentry, vercel, posthog }), {
      label: `correlate:${c.issueId}`,
      phase: 'Correlate',
      schema: CORRELATE_SCHEMA,
    })
    return { ...r, recon: { sentry, vercel, posthog }, correlation }
  },
)

const done = results.filter(Boolean).map(({ c, s, recon, correlation }) => ({
  issueId: c.issueId,
  title: c.title,
  isBug: c.isBug,
  classifyReason: c.reason,
  status: s ? s.status : 'failed',
  worktree: s && s.worktree,
  branch: s && s.branch,
  summaryPath: s && s.summaryPath,
  notes: s && s.notes,
  reconRan: !!recon,
  reconFound: recon
    ? { sentry: !!(recon.sentry && recon.sentry.found), vercel: !!(recon.vercel && recon.vercel.found), posthog: !!(recon.posthog && recon.posthog.found) }
    : null,
  hypothesis: correlation ? `${correlation.hypothesis} (confidence: ${correlation.confidence})` : null,
}))

const dropped = issues.length - done.length
if (dropped > 0) log(`${dropped} issue(s) dropped by agent failures — check the journal`)

return { dryRun, issues: done }
