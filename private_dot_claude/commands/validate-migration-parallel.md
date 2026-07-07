---
description: Run kysely-migration validation, fanning the independent checks out to parallel subagents.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__save_issue
---

# /validate-migration-parallel

This is the parallel form of `/validate-migration`. The validation criteria below are
mostly **independent, read-only audits** — they each inspect the migrated endpoint and
report whether a rule holds. Independent audits run concurrently as subagents; anything
that edits code runs sequentially afterward so two agents never write the same file at once.

Before starting, invoke the **`checklist` skill** and create one task per bullet/validation step.

## How to run it

1. **Fan out (parallel).** Dispatch the audit subagents below in a **single message with
   multiple `Task` calls** so they execute concurrently. Each is read-only: it inspects the
   code and returns a structured verdict (`PASS` / `FAIL` + file:line evidence + suggested
   fix). No audit subagent edits files.

2. **Collect.** Wait for all audits to return. Build one consolidated findings list.

3. **Fix (sequential).** Apply fixes yourself, one file at a time, in the main thread. Do
   not parallelize edits — concurrent writes to shared handlers/services will clobber each
   other.

4. **Re-validate.** Re-run only the audits whose findings you changed code for, to confirm they now pass.

### Global constraints — pass these verbatim to every subagent

These are hard rules every audit must respect and flag violations of:

- You are **not allowed to change the `withAdminDB` helper**. New reasons for bypassing via
  `withAdminDB` are fine; changing the helper itself is not. **No new helpers.**
- You are **not allowed to add new `AuthContext`s** — must reuse an existing one.
- **Do not use `BaseContext` as a type outside of the `kysely.ts` file.**
- **No type smuggling via `unknown`.**
- **No constants for grouping column names** — inline them so queries stay readable.
- Use the **adaptyv mcp** when necessary.

## Parallelizable audit subagents

Dispatch these concurrently. Each returns: verdict, evidence (`file:line`), and a proposed fix.

- **Audit A — smoketest (before/after).** Run the api smoketest and validate everything works
  correctly comparing before and after. Report any diffs (response-timestamp-type metadata
  changing is fine; payload differences are failures).

- **Audit B — non-GET endpoint parity.** The smoketest harness only covers GET routes. For
  every non-GET endpoint on this handler, `curl` before/after with an **identical payload
  body** and diff the responses. Report any non-metadata difference as a failure. Enumerate
  the full endpoint list so nothing is skipped.

- **Audit C — `@deprecated` ServiceContext removal.** Confirm the `@deprecated`
  ServiceContext is removed and replaced with a kysely one in this endpoint/handler **and the
  services it owns**. Use the **typescript lsp** to find any missed `@deprecated` context
  usage. Report every remaining reference with `file:line`.

- **Audit D — query & rpc migration.** Confirm all queries are migrated to kysely. Where rpcs
  are used, confirm they are migrated to **parametrized kysely queries** (we want full type
  checker coverage). Report any raw query / un-migrated rpc with `file:line`.

- **Audit E — constraint sweep.** Verify the global constraints above hold: no change to
  `withAdminDB`, no new helpers, no new `AuthContext`, no `BaseContext` type used outside
  `kysely.ts`, no `unknown` type smuggling, no column-name grouping constants. Report each
  violation with `file:line`.

- **Audit F — constraint sweep.** Run the entire test suite for the entire monorepo.

- **Audit G — migration-specific tests** Run the entire migration-specific tests (integration/unit).

### Sequencing notes

- Audits **A** and **B** exercise the running service (before/after compare) — they only
  read, so they're safe to run alongside the static audits (**C**, **D**, **E**).
- All five audits are read-only and have no inter-dependencies, so they all go in the same
  fan-out batch.
- The **fix** phase that follows is sequential and owned by the main thread.

## Done criteria

All audits report `PASS` (after fixes + re-validation), every endpoint — GET and non-GET —
matches before/after on payload, and every global constraint holds.
