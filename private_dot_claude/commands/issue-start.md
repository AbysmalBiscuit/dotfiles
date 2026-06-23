---
description: Cold-start a session inside an issue worktree — load the ISSUE_SUMMARY handoff and orient
allowed-tools: Bash, Read, Glob, Grep, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__save_issue, mcp__linear__save_comment, mcp__plugin_sentry_sentry__search_issues, mcp__plugin_sentry_sentry__find_projects, mcp__plugin_sentry_sentry__execute_sentry_tool, mcp__plugin_sentry_sentry__get_sentry_resource
---

# /start-issue

Pick up work in a worktree created by `/setup-issue`. Loads the session-summary
handoff, verifies the workspace, and orients before any code changes.

Run this from **inside the worktree dir** (e.g. `/home/lev/Git/adaptyv/eng-1234-...`).

## Input

`$ARGUMENTS` = optional issue ID (e.g. `ENG-1234`). If empty, auto-detect (step 1).

## Steps

Before step 1, invoke the **`checklist` skill** and create one task per numbered
step below (identify issue → load summary → verify workspace → orient → check Linear
+ Sentry assignment → hand control back). Mark each `in_progress` before starting it
and `completed` once done, so progress stays visible throughout.

### 1. Identify the issue

- If `$ARGUMENTS` set → `ISSUE_ID = $ARGUMENTS`.
- Else auto-detect from the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

  Branch looks like `<prefix>/eng-1234-...` (prefix may be `AbysmalBiscuit-claude/`,
  `lev/`, or a Linear-generated prefix). Extract the `ABC-123` identifier (uppercased)
  from the slug regardless of prefix → `ISSUE_ID`.
- If neither works (detached HEAD, no match), ask the user for the issue ID.

### 2. Load the summary

Read `/home/lev/Git/adaptyv/ISSUES_COMMON.md`.

Read `/home/lev/Git/adaptyv/ISSUE_SUMMARY_${ISSUE_ID}.md`.

- If missing, list `/home/lev/Git/adaptyv/ISSUE_SUMMARY_*.md` and ask which one
  (or whether to run `/setup-issue` first).
- Read it fully. This is the source of truth for the task: Linear/Notion links,
  summary, relevant info, suggested first steps.

### 3. Verify the workspace

```bash
pwd
git status --short
git rev-parse --abbrev-ref HEAD
```

Confirm: cwd is the worktree, branch matches the summary, tree clean. Flag any
mismatch (wrong dir, wrong branch, uncommitted leftovers) to the user.

Check deps are installed for the in-scope app(s) — if `node_modules` missing,
note it and offer to `bun install`.

### 4. Orient

- Restate the task in 2-3 lines from the summary.
- Surface how to start servers: `devrun up` (every in-scope app) or `devrun up <app>`,
  then `devrun status` for the ports devrun assigned. devrun reserves a collision-free
  port per app for the worktree, wraps each launch in doppler `dev_local`, and wires the
  API URL into consumer apps — so there's no port slot, literal launch command, or
  API-URL caveat to surface.
- Surface the **Suggested first steps** from the summary.
- If the summary lists a **Sentry** issue, surface its URL + short ID, and remind that
  the GitHub PR for this work must reference it in its description (see step 5).
- Surface the **Definition of done**: the fix must ship with unit and/or
  integration tests that reproduce the bug and fail without the fix, so this
  regression can't recur. Flag it now so test-writing is planned into the approach,
  not bolted on at the end.
- If the issue needs deeper context (acceptance criteria, linked PRs), offer to
  re-fetch the Linear issue via MCP — don't auto-fetch.

### 5. Check Linear + Sentry assignment

**Linear** — fetch the issue's current assignee (`mcp__linear__get_issue` for `ISSUE_ID`).

- **No one assigned** → assign the user to the issue (`mcp__linear__save_issue`,
  resolving the user via `mcp__linear__get_user` with `me`).
- **Someone already assigned** →
  - If `$ARGUMENTS` (or the conversation) included explicit permission to
    double-assign or reassign → proceed with the assignment.
  - Otherwise → **stop and ask the user** what to do (leave as-is, add self as a
    second assignee, or reassign to self). Do not change the assignee until they
    answer.

**Sentry** — make sure the related Sentry issue (if any) is owned and linked.

- If the summary already lists a **Sentry** issue → confirm it's assigned to the user
  in Sentry; assign it (`mcp__plugin_sentry_sentry__execute_sentry_tool`) if not.
- If the summary lists **no Sentry** issue → do one fresh search
  (`mcp__plugin_sentry_sentry__search_issues`) using the error text / affected module /
  in-scope app from the summary. Judge relevance strictly (same error, stack frame, or
  component). If a single clearly-relevant issue turns up:
  - assign it to the user in Sentry,
  - add a Linear comment (`mcp__linear__save_comment`) with the Sentry URL + short ID,
  - and note it back in the summary so the PR can reference it.
  Multiple candidates → list them and ask before claiming any. No clear match → skip.
- Either way, when a Sentry issue is in play, **remind the user**: the GitHub PR for
  this work must reference the Sentry issue in its description (e.g. a `Fixes: {URL}`
  line) so the error, Linear issue, and PR are cross-linked.

### 6. Hand control back

Ask the user how they want to proceed (e.g. start with first suggested step,
explore a specific file, or brainstorm approach). Don't start editing code
unsolicited.

## Notes

- Dev servers run through `devrun`, which wraps launches in doppler `dev_local`
  automatically — never run `doppler` by hand or against prod (`prd`).
- This command orients only — it does not write code or commit.
