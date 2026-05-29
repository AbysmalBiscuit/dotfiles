---
description: Cold-start a session inside an issue worktree — load the ISSUE_SUMMARY handoff and orient
allowed-tools: Bash, Read, Glob, Grep
---

# /start-issue

Pick up work in a worktree created by `/setup-issue`. Loads the session-summary
handoff, verifies the workspace, and orients before any code changes.

Run this from **inside the worktree dir** (e.g. `/home/lev/Git/adaptyv/eng-1234-...`).

## Input

`$ARGUMENTS` = optional issue ID (e.g. `ENG-1234`). If empty, auto-detect (step 1).

## Steps

### 1. Identify the issue

- If `$ARGUMENTS` set → `ISSUE_ID = $ARGUMENTS`.
- Else auto-detect from the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

  Branch looks like `AbysmalBiscuit-claude/eng-1234-...`. Extract the `ABC-123`
  identifier (uppercased) from the slug → `ISSUE_ID`.
- If neither works (detached HEAD, no match), ask the user for the issue ID.

### 2. Load the summary

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
- Surface the **Suggested first steps** from the summary.
- If the issue needs deeper context (acceptance criteria, linked PRs), offer to
  re-fetch the Linear issue via MCP — don't auto-fetch.

### 5. Hand control back

Ask the user how they want to proceed (e.g. start with first suggested step,
explore a specific file, or brainstorm approach). Don't start editing code
unsolicited.

## Notes

- Never run `doppler` unless asked explicitly.
- This command orients only — it does not write code or commit.
