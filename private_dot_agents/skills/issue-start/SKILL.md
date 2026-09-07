---
name: issue-start-ist
description: Cold-start a session inside an issue worktree — load the ISSUE_SUMMARY handoff and orient
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__save_issue, mcp__linear__save_comment, mcp__plugin_sentry_sentry__search_issues, mcp__plugin_sentry_sentry__find_projects, mcp__plugin_sentry_sentry__execute_sentry_tool, mcp__plugin_sentry_sentry__get_sentry_resource
---
# /issue-start

Pick up work in a worktree created by `/issue-setup`. Loads the session-summary
handoff, verifies the workspace, and orients before any code changes.

Run this from **inside the worktree dir**.

## Input

`$ARGUMENTS` = optional issue ID (e.g. `ENG-1234`). If empty, the recon script derives
it from the devkit record, then the branch name.

## What already happened

`~/.agents/skills/issue-start/scripts/issue_start_context.py` has **already run**,
read-only. It resolved the worktree, the issue id, the session summary, the
working-tree state and whether the installed dependencies match the lockfile. Its
output is below.

It ends with `IC-RESULT: <STATUS>`. Everything you need about the worktree, the issue,
the summary and the tree is in that output. Do not re-run `git status`, `git rev-parse`,
`ls`, or `cat` on the summary to orient yourself.

The summary is the source of truth for the task: tracker links, what the issue is,
suggested first steps. Read the whole thing in the output above before acting.

---

!`python3 ~/.agents/skills/issue-start/scripts/issue_start_context.py "$ARGUMENTS" 2>&1 || true`

---

## Act on the result

| `IC-RESULT` | What to do |
|---|---|
| `READY` | Worktree, issue and summary all resolved. Work the steps below. |
| `NO-SUMMARY` | No handoff exists. If the script listed other summaries in that directory, ask which one applies. Otherwise ask whether to fetch the issue from the tracker and continue without a handoff, or run `/issue-setup` first. |
| `NOT-ISSUE-WORKTREE` | No issue id in the devkit record or the branch. Ask the user which issue this worktree is for, then re-run with it as the argument. Stop. |
| `PROTECTED` | You're on a base branch, not an issue worktree. Report it and ask which worktree they meant. Stop. |
| `ERROR` | Not a repo, or detached HEAD. Report the message and stop. |

On `READY` or a resolved `NO-SUMMARY`, invoke the **`checklist` skill** and create one
task per numbered step below. Mark each `in_progress` before starting it and `completed`
once done. On any other result there is nothing to track: report and stop.

## Steps

### 1. Orient

- Restate the task in 2-3 lines from the summary.
- Flag anything the `== workspace ==` block reported: a dirty tree, no upstream, or a
  lockfile newer than the installed tree. Offer to run the install it names rather than
  running one unasked.
- Surface how to start servers: `devrun up` (every in-scope app) or `devrun up <app>`,
  then `devrun status` for the ports devrun assigned. devrun reserves a collision-free
  port per app for the worktree and applies whatever secret-injection and cross-app URL
  wiring the devkit config declares — so there's no port slot, literal launch command,
  or env caveat to surface. `devkit config apps` lists the app ids.
- Surface the **Suggested first steps** from the summary.
- If the summary lists a **Sentry** issue, surface its URL + short ID, and remind that
  the GitHub PR for this work must reference it in its description (see step 2).
- Surface the **Definition of done**: the fix must ship with unit and/or
  integration tests that reproduce the bug and fail without the fix, so this
  regression can't recur. Flag it now so test-writing is planned into the approach,
  not bolted on at the end.
- If the issue needs deeper context (acceptance criteria, linked PRs), offer to
  re-fetch the tracker issue via MCP — don't auto-fetch.
- Use the `/graphify` skill to trace the issue more quickly than just grepping.

### 2. Check Linear + Sentry assignment

Skip either half when the project doesn't use that tracker.

**Linear** — fetch the issue's current assignee (`mcp__linear__get_issue` for the issue
id the script resolved).

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
  line) so the error, tracker issue, and PR are cross-linked.

### 3. Hand control back

Ask the user how they want to proceed (e.g. start with first suggested step,
explore a specific file, or brainstorm approach). Don't start editing code
unsolicited.

## Notes

- Dev servers run through `devrun`, which injects the project's dev secrets itself —
  never invoke the secrets tool by hand, and never against a production config.
- This command orients only — it does not write code or commit.
