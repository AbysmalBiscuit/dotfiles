---
description: Set up an issue worktree via /issue-setup for a kysely-migration sweep issue
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__list_comments
---

# /issue-setup-migration

Bootstrap an isolated worktree for one of the kysely-migration **sweep** issues.

This is a thin wrapper around `/issue-setup`: it runs the full setup flow with the
given issue number, framed for the kysely `@deprecated` ServiceContext → kysely
migration sweep so the session handoff points the next session at the migration
playbook.

## Input

`$ISSUENUMBER` = the Linear issue ID (e.g. `ENG-1234`) or a Linear issue URL for the
sweep issue to set up.

If `$ISSUENUMBER` is empty, ask the user for the issue ID/URL before doing anything.

## Steps

### 1. Run the issue-setup flow

Invoke the **`issue-setup` skill** with `$ISSUENUMBER` and complete every step it
defines (fetch issue → derive names → create worktree → install deps →
write summary → report back). Do not skip or reorder its steps.

### 2. Flag it as a kysely-sweep migration

When writing the session summary (issue-setup step 7), make the migration context
explicit so the cold-start session knows what it's picking up:

- In **Suggested first steps**, lead with: run `/issue-start-migrate` inside the
  worktree to cold-start and carry out the `@deprecated` ServiceContext → kysely
  migration under its fixed directives.
- Note in **Relevant info** that this is part of the kysely migration sweep.

Everything else (report-back, devrun-based server startup) stays exactly as
`/issue-setup` defines it.
