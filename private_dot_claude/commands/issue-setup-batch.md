---
description: Set up worktrees for multiple Linear issues at once — bugs get Sentry/Vercel/PostHog recon, everything else gets plain setup
allowed-tools: Bash, Read, Workflow, TaskOutput, AskUserQuestion
argument-hint: "<ENG-1234 ENG-1235 https://linear.app/... — space/comma/newline separated> [--dry-run]"
---

# /issue-setup-batch

Batch front-end for the `batch-issue-setup` workflow (`~/.claude/workflows/batch-issue-setup.js`).
The workflow triages each issue (bug vs not), runs the full `/issue-setup` flow per issue
with git operations serialized, fans Sentry/Vercel/PostHog recon out for bugs only, and
appends a correlated hypothesis to each bug's session summary.

## Input

`$ARGUMENTS` = any mix of Linear issue IDs (`ENG-1234`) and Linear URLs, separated by
spaces, commas, or newlines. An optional `--dry-run` flag anywhere in the input previews
branch/worktree/ports without creating anything (recon is skipped too).

## Steps

### 1. Parse the issue list

- Extract every issue reference: bare IDs matching `[A-Za-z]+-\d+` and `linear.app` URLs
  (keep URLs whole — the workflow parses them).
- Ignore surrounding punctuation and markdown link syntax; dedupe case-insensitively by ID.
- `--dry-run` (or `dry run`) anywhere sets `dryRun: true` and is not an issue.
- If nothing parses to an issue reference, ask the user for the list before doing anything.

### 2. Run the workflow

Invoke the **Workflow** tool:

```
{ name: "batch-issue-setup", args: { issues: [<parsed list>], dryRun: <bool> } }
```

Pass `issues` as a real JSON array, not a stringified one. The workflow runs in the
background; tell the user it's running and that `/workflows` shows live progress, then
wait for the task notification.

### 3. Report back

From the workflow's returned `issues` array, print:

- A table: issue ID, title, bug?, setup status, recon (which of sentry/vercel/posthog
  found anything, or "—").
- Per successful issue, copyable lines: `cd <worktree>` (unquoted when the path needs no
  quoting), the summary file path, and the branch.
- Per bug with recon, the one-line leading hypothesis.
- **Blocked/failed issues called out explicitly** with their `notes` (e.g. branch already
  exists, Sentry ambiguity) and what the user should decide. Do not silently drop them.
- Remind: `devrun up` + `devrun status` inside each worktree; bugs continue with
  `/issue-start` in the worktree (graphify tracing and git archaeology were deliberately
  deferred to that session).

If the workflow result is empty or missing issues that were passed in, read the run's
`journal.jsonl` (path in the Workflow tool result) before diagnosing — do not guess.
