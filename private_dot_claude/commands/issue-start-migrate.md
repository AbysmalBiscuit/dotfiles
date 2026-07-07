---
description: Cold-start an issue worktree via /issue-start, then do the kysely ServiceContext→kysely migration under fixed directives
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__save_issue
---

# /issue-start-migrate

Cold-start a session inside an issue worktree and then **do the
`@deprecated` ServiceContext → kysely migration**.

This is `/issue-start` plus a migration playbook. Unlike `/issue-start`, this command
*does* proceed into code: after orienting, start executing the migration under the
directives below. They are the contract for *how* the migration must be done; they are
not optional.

## Input

`$ARGUMENTS` = optional issue ID (e.g. `ENG-1234`). If empty, auto-detect from the
current branch (same as `/issue-start`).

## Steps

Before step 1, invoke the **`checklist` skill** to track this command's two phases
(run the issue-start flow → do the migration). As the migration takes shape in step 2,
add one task per concrete migration action (smoketest, remove `@deprecated` context,
migrate queries, validate every endpoint, etc.) so each is checked off as it lands.
Mark exactly one task `in_progress` at a time and `completed` once verified.

### 1. Run the issue-start flow

Invoke the **`issue-start` skill** with `$ARGUMENTS` and complete every step it
defines (identify issue → load summary → verify workspace → orient → check Linear
assignment). Do not skip or reorder its steps.

### 2. Do the migration

Once oriented, begin the migration. Follow these directives exactly:

Goal: do the migration. Validate that everything works correctly **before and after**.

- Run the api smoketest.
- Remove the `@deprecated` ServiceContext from this endpoint/handler **and the
  services it owns**, replacing it with a kysely one. Use the TypeScript LSP to
  confirm no `@deprecated` context usage was missed anywhere here.
- Validate **all** endpoints. The smoketest harness only covers GET routes, so for
  every non-GET route use `curl` to capture before/after responses yourself. Keep
  the request payload body identical across before/after; metadata that legitimately
  changes (e.g. response timestamps) is fine.
- Migrate queries to kysely.
- Do **not** change the `withAdminDB` helper. You may add new reasons for bypassing
  via `withAdminDB`, but you may not modify the helper and you may not add any new
  helpers.
- Do **not** add new AuthContexts — use one of the existing ones.
- Do **not** use `BaseContext` as a type outside of the `kysely.ts` file.
- When RPCs are used, migrate them to **parametrized kysely queries** so the type
  checker is fully engaged.
- Use the adaptyv MCP when necessary.
- No type smuggling via `unknown`.
- Do not create constants for grouping column names — inline them so the queries
  stay readable.
- Add http e2e integration tests.

> The `/issue-start` "orient only, don't edit code" rule is overridden here — this
> command's purpose is to carry out the migration once the workspace is confirmed.
