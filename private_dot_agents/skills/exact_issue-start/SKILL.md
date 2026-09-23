---
name: issue-start-ist
description: "Use when cold-starting a session inside an issue worktree."
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__save_issue, mcp__linear__save_comment, mcp__plugin_sentry_sentry__search_issues, mcp__plugin_sentry_sentry__find_projects, mcp__plugin_sentry_sentry__execute_sentry_tool, mcp__plugin_sentry_sentry__get_sentry_resource
---

# /issue-start

Load the session-summary handoff and orient inside an issue worktree created by `/issue-setup`. This workflow ends before implementation.

Takes an optional issue ID. Without one, the script resolves it from the devkit record, then the branch name.

## Run the script

When the user invokes this workflow, run the following read-only command with the shell tool's working directory set to the target worktree. Reading or editing this skill alone does not invoke the workflow.

```bash
python3 /home/lev/.agents/skills/issue-start/scripts/issue_start_context.py
```

If the user supplied an issue ID, append it as one shell-quoted argument. Read it from the invocation or user request; `$ARGUMENTS` is not a shell variable to rely on. Keep the same worktree for retries.

Wait for completion and read stdout and stderr, including on a nonzero exit. The last line is `IC-RESULT: <STATUS>`. If no marker appears, diagnose the execution failure before retrying. A command shown here is not evidence that it ran.

Read the whole summary in the output; it is the task handoff. Reuse the reported workspace and dependency checks. Make additional queries only to resolve missing information, a reported failure, or an ambiguity.

## Act on the result

| `IC-RESULT` | What to do |
|---|---|
| `READY` | Worktree, issue and summary resolved. Continue below. |
| `NO-SUMMARY` | If other summaries were listed, ask which applies and read the selected handoff. Otherwise ask whether to fetch the tracker issue and continue without a handoff, or run `/issue-setup` first. Continue below only after obtaining the selected handoff or authorized tracker context. |
| `NOT-ISSUE-WORKTREE` | Ask which issue this worktree is for. Wait for the answer, then re-run with that issue ID and act on the new result. |
| `PROTECTED` | You're on a base branch, not an issue worktree. Report it and ask which worktree they meant. Stop. |
| `ERROR` | Not a repo, or detached HEAD. Report the message and stop. |

## Orient and hand back

### 1. Orient

- Summarize the task, suggested first steps, and definition of done from the handoff. For a bug fix, include tests that reproduce the bug and fail without the fix.
- Report a dirty tree, missing upstream, or missing/stale dependencies. Offer the install command the script names; run it only when authorized.
- If acceptance criteria or linked work are missing, offer to fetch that context from the tracker. The assignment lookup below is separate.
- Use the `graphify` skill when tracing the issue into the codebase.

### 2. Check tracker ownership

If the project uses Linear or Sentry, read and follow [references/trackers.md](references/trackers.md). Continue once applicable checks are complete; report any unavailable tracker access as an outstanding check.

### 3. Hand control back

Report the orientation and tracker results, including outstanding checks. Recommend one next action and ask whether to proceed. If the user already requested that action in the conversation, continue with it after orientation.
