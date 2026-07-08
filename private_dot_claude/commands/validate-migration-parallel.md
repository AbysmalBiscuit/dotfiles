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

- **Audit G — migration-specific tests + CI-safety.** Two parts, both required:
  - **G1 — run them.** Run the entire migration-specific test set (integration/unit)
    against a local DB with writes enabled (`ALLOW_DB_WRITES=true doppler run -p api-foundry
    -c dev_local -- bun test <files>`). All must pass. A fresh worktree needs `bun install`
    then `nitro prepare` first, or the `~/…` alias fails to resolve and every test errors at
    import.
  - **G2 — prove they don't trip CI.** A migration suite that passes locally (with a DB) can
    still **fail the whole `@adaptyv/api` test job in CI**, which runs with **no DB** and sets
    `TEMPORARY_CI_DB_SKIP=1`. The trap: DB-gated suites must **skip**, not throw, in that
    environment. Verify the new/changed test files follow the established gating in
    `tests/integration/_setup.ts` + `tests/integration/README.md`:
    - The suite is wrapped in `describe.skipIf(CI_DB_SKIP)(…)` (import `CI_DB_SKIP` from
      `../_setup`) and carries the correct `[supabase:readonly|write]` tag.
    - **No `throw`, no `await isDbAvailable()`, and no seeding at module scope** that runs
      before `describe.skipIf` can skip it. Any fail-loud "requires a local DB" guard must be
      gated behind `if (!CI_DB_SKIP)` (prod-safety checks may stay unconditional). A top-level
      `throw` surfaces in CI as an **"Unhandled error between tests"** and reds the job.
    - **`describe.skipIf` skips test/hook *execution*, NOT body *evaluation*.** bun evaluates a
      skipped describe callback to register its tests, so any DB-touching call placed **at
      describe scope** still runs — and throws — under `CI_DB_SKIP`, even though it looks
      guarded by the `skipIf`. The classic offender is a Kysely handle built eagerly:

      ```ts
      // ❌ throws at collection time on the DB-less runner — createTestKysely() runs
      //    when the describe body is evaluated, before skipIf skips the tests
      describe.skipIf(CI_DB_SKIP)("[supabase:write] …", () => {
          const ky = createTestKysely();
          beforeAll(async () => { await seed(ky); });
      });

      // ✅ defer into beforeAll — skipped suites never touch the DB factory
      describe.skipIf(CI_DB_SKIP)("[supabase:write] …", () => {
          let ky: Kysely<ExtendedDB>;
          beforeAll(async () => { ky = createTestKysely(); await seed(ky); });
      });
      ```

      A DB handle must be created inside `beforeAll` (assign to a `let`) — or, if it must be
      module/describe scope, behind the ternary the codebase uses:
      `const ky = CI_DB_SKIP ? null : createTestKysely()`. Never call `createTestKysely()`
      bare at module or describe scope.
    - Confirm empirically: `TEMPORARY_CI_DB_SKIP=1 bun test <files>` (no doppler, no DB) must
      exit **0** with the suite **skipped** and **zero** unhandled errors. Report a `FAIL` with
      `file:line` for any suite that throws or runs at module scope under this flag.

### Sequencing notes

- Audits **A** and **B** exercise the running service (before/after compare) — they only
  read, so they're safe to run alongside the static audits (**C**, **D**, **E**).
- All five audits are read-only and have no inter-dependencies, so they all go in the same
  fan-out batch.
- The **fix** phase that follows is sequential and owned by the main thread.

## Done criteria

All audits report `PASS` (after fixes + re-validation), every endpoint — GET and non-GET —
matches before/after on payload, every global constraint holds, and the migration test
files are **CI-safe** (Audit G2): they skip cleanly under `TEMPORARY_CI_DB_SKIP=1` with no
module-scope throw, so they don't red the `@adaptyv/api` test job on the DB-less CI runner.
