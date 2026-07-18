---
name: issue-setup-bug
description: "Set up an issue worktree via $issue-setup for a bug, fanning Vercel/Sentry/PostHog recon out to subagents, then tracing the error path with $graphify Use when the user invokes $issue-setup-bug or asks for this workflow."
---

# $issue-setup-bug

Bootstrap an isolated worktree for a **bug**, and arrive in it already knowing what
broke, when it started, and which code path produced it.

This is `$issue-setup` plus a recon phase. Three subagents interrogate the three places
that independently witnessed the bug — **Vercel** (what shipped), **Sentry** (what threw),
**PostHog** (who hit it) — while the main session traces the error back through the code
with **`$graphify`**. If that trace lands on a probable cause, a fourth subagent goes into
the **git history** of exactly that code to find when and what changed.

The point of splitting it this way: each source knows one axis of the same incident and is
blind to the others. Sentry gives you a stack trace but not the deploy that introduced it.
Vercel gives you deploy times but not what broke. PostHog gives you blast radius and flag
state but not the exception. **The value is in the correlation** — an error whose
`firstSeen` lands minutes after a deploy has a prime suspect; one that tracks a feature
flag rollout instead has a different one. Produce that correlation, don't just staple three
reports together.

The git dig is deliberately **conditional and last**. Blaming a file before you know which
frame throws just produces a list of everyone who ever touched it. Once `$graphify` names a
specific function, the same commands stop being archaeology and become an answer: this line,
this commit, this PR, this day.

## Input

`<USER_INPUT>` = whatever identifies the bug:

- a Linear issue ID (`ENG-1234`) or URL,
- a Slack thread URL (permalink to the report), **or**
- a free-text description of the broken behavior.

If `<USER_INPUT>` is empty, ask the user for one of the above before doing anything.

## Steps

Before step 0, invoke the `checklist` skill and create one plan item per numbered step,
plus one per sub-agent once step 2 dispatches them. Keep exactly one item `in_progress`.

Stop and ask the user if any step is ambiguous. Recon is **read-only**: this command never
resolves a Sentry issue, never redeploys, never mutates PostHog.

### Parallel execution

Only step 0 is a hard prerequisite. Batch independent calls into single messages.

- **Wave A** — step 0 (establish the error signature). Everything downstream needs it.
- **Wave B** (concurrent) — step 1 (`$issue-setup` builds the worktree) **and** step 2
  (the three recon subagents). They share nothing; run them at the same time.
- **Wave C** — step 3 (`$graphify` trace). Needs the worktree from step 1; its queries are
  sharpest once Sentry's stack frames land from step 2. Start indexing as soon as the
  worktree exists rather than waiting on the subagents.
- **Wave D** — step 4 (git archaeology), **only if** step 3 produced a probable cause. This
  one is serial by necessity: it needs the exact file and function that step 3 names.
- **Wave E** — step 5 (correlate) then step 6 (write the summary).

### 0. Establish the error signature

Extract the facts every other step keys off. Pull them from whichever input you got:

- **Linear** — `get_issue` + `list_comments`. Scan for stack traces, request IDs, screenshots.
- **Slack** — `slack_read_thread` on the permalink; the original report and the replies
  usually carry the timestamp and the affected user.
- **Free text** — take the user's words, then ask for anything missing below.

Write down, explicitly:

| Field | Why it matters |
|---|---|
| **Error message / exception type** | The Sentry + PostHog search key. |
| **Stack frame or culprit** (file:function) | Seeds the `$graphify` trace in step 3. |
| **Entry point** (route, endpoint, UI action, job) | Where to reproduce it. |
| **Time window** (first report → now) | Correlates against deploys and flag rollouts. |
| **Environment** (prod / preview / staging) | Scopes every query. |
| **Affected app** | Picks the Vercel project and Sentry project. |

If you can't name the error message *or* the entry point, ask the user before dispatching
subagents — three agents searching for the wrong string is worse than one clarifying question.

### 1. Run the issue-setup flow

Invoke the **`issue-setup` skill** with the Linear issue ID and complete every step it
defines (fetch issue → find/assign Sentry issue → derive slug + apps → `issue setup` →
write summary → report back). Do not skip or reorder its steps.

If the input was a Slack thread or free text with **no Linear issue**, say so and ask the
user whether to create one or proceed with a worktree named from a slug you propose.
`$issue-setup` expects an issue ID; don't invent one.

### 2. Recon — three subagents, dispatched together

Spawn all three Codex sub-agents before waiting so they run concurrently. Give each one
the full error signature from step 0. Each is **read-only** and
must return a compact structured report — not a log dump. Instruct each: *if your source
has nothing on this error, say so plainly; do not pad with plausible-sounding findings.*

**Subagent A — Vercel (what shipped).** There is no Vercel MCP; shell out to the `vercel`
CLI. If it isn't authenticated, report that rather than guessing.

```bash
vercel ls <project>                  # recent deployments + timestamps
vercel inspect <deployment-url>      # commit sha, author, build status
vercel logs <deployment-url>         # runtime + build errors
```

Return: deployments landing inside the time window, each with **timestamp, commit sha,
author, PR**; any build/runtime errors; and the deploy immediately preceding the error's
first occurrence — the prime suspect.

**Subagent B — Sentry (what threw).** Narrow with `find_projects`, then `search_issues` on
the error message / exception type, scoped to the environment. On the best match pull the
full stack trace, `culprit`, `firstSeen` / `lastSeen`, release, event count, and users
affected. `search_events` gives the per-event detail; consider `analyze_issue_with_seer` for
a root-cause hypothesis when the trace is deep.

Return: issue URL + short ID, **exact `firstSeen` timestamp**, the release it appeared in,
frequency and user count, and the **top 3 application stack frames** (skip vendor/node_modules
frames — those are what step 3 needs to start from).

**Subagent C — PostHog (who hit it).** Use the configured PostHog integration for HogQL
over the events table and the error-tracking/session-replay surfaces.

Return: how many distinct users hit it and whether they cluster (one org? one browser? one
plan tier?); any **feature flag** enabled for the affected users but not the unaffected ones;
session replay links for 1–2 representative failures; and the event volume curve across the
time window — did it start abruptly (deploy) or ramp (rollout)?

### 3. Trace the error path with `$graphify`

In the **main session**, inside the worktree, invoke the **`graphify` skill**. Build (or
reuse) the knowledge graph for the affected app, then query it to trace the failure.

Seed the trace from the strongest signal you have, in this order of preference:

1. Sentry's top application stack frame (step 2B) — the most precise entry.
2. The culprit / file:function named in the Linear issue or Slack thread.
3. The entry point from step 0, if no frame is available.

Ask the graph the questions a human debugger would:

- What is the **call path** from the entry point (route/handler) to the throwing frame?
- What does that frame **depend on** — which services, queries, helpers, external calls?
- Which of those were **touched by the suspect deploy** from step 2A? (Intersect the graph
  neighborhood with the commit's changed files. This is the money question.)
- Where are the **unguarded assumptions** on that path — unchecked nulls, unvalidated input,
  an `any` cast, a missing `await`?

Output a short call-path narrative, not a node dump: *"`POST /x` → `handlerY` →
`serviceZ.fetch()` → throws at `parseRow()` because column `foo` is null since migration
`abc`."*

End with an explicit verdict: **probable cause = `<file>:<function>`**, or **no probable
cause** and why. Step 4 keys off that verdict.

### 4. Git archaeology — conditional, one subagent

**Only run this if step 3 named a probable cause.** The gate: the trace must point at a
specific `file:function`, *and* at least one of —

- Sentry's top application frame lands in it, **or**
- it sits in the suspect deploy's changed files (step 2A), **or**
- it contains the unguarded assumption that explains the exception (the null deref, the
  missing `await`, the unvalidated field).

If none of those hold, **skip this step and say so.** A `git blame` on a file you merely
suspect returns everyone who ever touched it — noise that reads like evidence. Dispatching
the agent anyway is worse than not dispatching it, because its output will look
authoritative.

When the gate passes, dispatch **one sub-agent** to answer *when* and *what* changed. It is
**read-only** — it never checks out, resets, or amends anything. Hand it the file, the
function, the throwing line numbers, Sentry's `firstSeen`, and the suspect commit from 2A.

```bash
git log -L <start>,<end>:<file>          # history of just those lines — the sharpest tool
git log -S '<symbol>' --oneline -- <file>  # pickaxe: commits that added/removed the symbol
git log -G '<regex>' --oneline -- <file>   # commits whose diff matched a pattern
git blame -L <start>,<end> -- <file>       # who last touched each throwing line
git show <sha> -- <file>                   # the actual hunk
```

Scope to commits landing **before** Sentry's `firstSeen` — the defect must predate the first
throw. `git log -L` is the one that usually answers it outright; reach for `blame` only to
attribute a specific line.

Return:

- The **commit that introduced the defect**: sha, author, date, PR number, subject.
- The **diff hunk** that did it — the few lines, not the whole commit.
- Whether that commit **is** the suspect deploy from 2A, precedes it, or contradicts it.
- **Regression or never-worked?** Did these lines once handle the case correctly and stop,
  or was the path never exercised until now? This changes the fix: a regression restores
  prior behavior, a never-worked path needs new handling.
- If the line's history is dominated by moves, renames, or a format-only commit, say so —
  `git log --follow` past a rename, and don't blame the reformatter.

If the history contradicts the step-3 hypothesis (the code hasn't changed since long before
`firstSeen`), that is a **finding, not a failure**. Report it plainly: the cause is upstream
of this code — data, a dependency bump, a config or migration change.

### 5. Correlate the sources

This is the step that earns the parallelism. Line the findings up against the time window:

- Does Sentry's `firstSeen` land **just after** a Vercel deploy? → that commit is the cause;
  name it, and diff it against the graph neighborhood from step 3.
- Does it instead track a **feature flag rollout curve** from PostHog? → the flag gates the
  broken path; the code may have shipped days earlier and lain dormant.
- Does it correlate with **neither**? → suspect data, not code: a migration, an upstream API
  change, an expired credential. Say so, and say what you'd check next.

Where step 4 ran, it is the tiebreaker: it dates the defect from the code itself rather than
inferring it from deploy timing. Treat a disagreement as signal, not noise —

- **Git commit == suspect deploy** → the strongest case you can build. Cause established.
- **Defect predates the deploy** → the deploy exposed dormant code; the flag rollout or a
  changed input reached it first. The commit to revert is *not* the deploy.
- **Code unchanged for months** → not a code cause at all, whatever the deploy timing
  suggests. Coincident deploys are common; believe the history.

State your **leading hypothesis and your confidence in it**, plus the single cheapest
experiment that would falsify it. A confident wrong hypothesis costs more than an honest
"four sources, no correlation — here's what I'd check."

### 6. Write the session summary

Extend the `ISSUE_SUMMARY_${ISSUE_ID}.md` that `$issue-setup` wrote (its step 5).
This is the cold-start handoff — a session that reads only this file must be able to pick up
the bug. Append:

```md
## Bug recon

- **Error:** {message / exception type}
- **Entry point:** {route / action / job}
- **Environment:** {prod | preview | staging}
- **Sentry:** {issue URL, short ID, firstSeen, release, N events / M users}
- **Suspect deploy:** {commit sha + PR + timestamp, or "none — see below"}
- **Feature flag:** {flag key if implicated, else "none"}
- **Blast radius:** {users / orgs affected, clustering}
- **Replays:** {1–2 PostHog session replay links}

## Call path

{the step-3 narrative: entry point → … → throwing frame, and why it throws}

## When it broke

- **Introducing commit:** {sha, author, date, PR, subject — or "not run: no probable cause"}
- **Offending hunk:** {the few lines that did it}
- **Regression or never-worked:** {restored prior behavior vs. new handling needed}
- **Agrees with suspect deploy?** {yes | predates it | contradicts it — code unchanged}

## Leading hypothesis

{one paragraph} — confidence: {low | medium | high}
Cheapest falsifying experiment: {what to run}

## Suggested first steps

1. Run `$issue-start` inside the worktree to cold-start.
2. Reproduce the failure end-to-end at the real entry point above, before changing anything.
3. Write the failing test first (RED), then fix.
4. Run `$validate-tdd` to prove the test actually exercises the bug — a test that passes
   with the fix reverted proves nothing.
```

Anything a source genuinely had nothing on gets written as **"none found"**. An empty field
is a finding; a fabricated one poisons the next session.

Everything else (report-back, devrun-based server startup) stays exactly as `$issue-setup`
defines it.
