---
description: Cold-start an issue worktree via /issue-start, then do the kysely ServiceContext→kysely migration under fixed directives
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__linear__get_issue, mcp__linear__get_user, mcp__linear__save_issue
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
- Add the migration test battery — see step 3.

### 3. Add the migration test battery

Tests are part of the migration, not an afterthought. **Which battery is mandatory
depends on the migration class** — match the tests to what you actually changed, and
follow `apps/api/tests/integration/README.md` ("Validating a migration") as the source
of truth. Do not over-test a plain swap or under-test a view/RPC port.

First classify the change:

- **Plain client swap** — you moved a handler/service off `ctx.db` (PostgREST) onto
  Kysely `ctx.replicaDB`/`ctx.primaryDB` but the *SQL shape is unchanged* (same tables/
  views selected, same columns). No hand-written SQL reimplements a view or RPC.
  Examples: the CRUD sweeps (`raw-sequences-*`, `experiment-update`, `public-results`).
- **View/RPC port** — you reimplemented a SQL **view** or a Postgres **RPC** as a Kysely
  builder (`services/<domain>/queries/<name>.ts`). The builder's output must be
  byte-identical to the source it replaces. Examples: `plate_experiments_v3`,
  `tasks_view`, the `*-realistic-scale` suites.

**Both classes ship one HTTP E2E suite** (`tests/integration/http-auth/<domain>.integration.test.ts`)
— real requests through the running app, never a bare query. It MUST:

- Gate + tag exactly like its peers: `[supabase:write]`, `describe.skipIf(CI_DB_SKIP)`,
  `await requireLocalWriteApi()` at module scope, and build the Kysely test handle
  **inside `beforeAll`** (never at module/describe scope — the describe body runs even
  when skipped, so a bare handle throws at collection under `TEMPORARY_CI_DB_SKIP=1`).
- Cover the **full auth matrix** via `resolveIdentities()` — `staff`, `customerMember`,
  **and `customerNonMember`**, plus anonymous. This is the sweep norm (~half the suites),
  including the plain-swap CRUD peers; do not ship a reduced anon/member/staff matrix.
  A staff-only endpoint still asserts the 403 for *both* customer classes. Add the
  `admin` identity only when the endpoint has an admin-vs-staff behaviour difference
  (e.g. an RLS-bypass/downgrade path).
- Assert the **behaviour contract**: ordering, every filter, and the **pagination
  corners including an out-of-range page** (a `count(*) OVER()` window wrongly reports
  total 0 there — the standalone count must still report the truth).
- For **every write path**: an **affected-row guard** (a 0-row `UPDATE` must 404/fail
  loud, not silently 200 — SWE-9967) and **A/B parity** — the endpoint response equals
  an *independent* post-write direct-SQL read of the row.
- Keep **one un-canonicalized timestamp assertion** to prove the wire format.

**View/RPC ports additionally ship** the other two mandatory layers (a plain swap does
NOT — there is no reimplemented SQL to diff, so these are noise there):

- **In-process corner-covering parity** (`_parity.ts`, `[supabase:readonly]`): compiled
  builder `==` source over a corner set discovered in the DB (UNION paths, empty, multi,
  no-chain, every column on its populated path, and the negatives — unknown id → empty,
  empty input → empty). `canonicalize` absorbs `array_agg` order + timestamp format.
- **Realistic-scale HTTP pass** (`_seed-realistic.ts` → `*-realistic-scale.integration.test.ts`):
  the query driven over HTTP on data generated to the source's **prod distribution**
  (proportions measured via the `postgres-readonly` MCP) — the layer that surfaces RLS
  O(N²), statement-timeouts, and window-count divergences a tiny seed never will.
- **Prod 0-divergence proof** (read-only `postgres-readonly` MCP): compiled builder vs
  live source over every prod row (`WHERE a IS DISTINCT FROM b`, expect `0`).

Response-schema (`.parse`) validation on responses is **not** a sweep requirement — only
a handful of suites do it; add it only if the endpoint's response contract is fragile.

> The `/issue-start` "orient only, don't edit code" rule is overridden here — this
> command's purpose is to carry out the migration once the workspace is confirmed.
