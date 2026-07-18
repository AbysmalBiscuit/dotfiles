---
name: issue-start-migrate
description: "Cold-start an issue worktree via $issue-start, then do the kysely ServiceContext→kysely migration under fixed directives Use when the user invokes $issue-start-migrate or asks for this workflow."
---

# $issue-start-migrate

Cold-start a session inside an issue worktree and then **do the
`@deprecated` ServiceContext → kysely migration**.

This is `$issue-start` plus a migration playbook. Unlike `$issue-start`, this command
*does* proceed into code: after orienting, start executing the migration under the
directives below. They are the contract for *how* the migration must be done; they are
not optional.

## Input

`<USER_INPUT>` = optional issue ID (e.g. `ENG-1234`). If empty, auto-detect from the
current branch (same as `$issue-start`).

## Steps

Before step 1, invoke the **`checklist` skill** to track this command's phases
(run the issue-start flow → do the migration → gate it behind a feature flag → add
the test battery). As the migration takes shape in step 2, add one task per concrete
migration action (smoketest, move the new path off the `@deprecated` context, migrate
queries, create + wire the feature flag, validate every endpoint, etc.) so each is
checked off as it lands. Mark exactly one task `in_progress` at a time and `completed`
once verified.

### 1. Run the issue-start flow

Invoke the **`issue-start` skill** with `<USER_INPUT>` and complete every step it
defines (identify issue → load summary → verify workspace → orient → check Linear
assignment). Do not skip or reorder its steps.

### 2. Do the migration

Once oriented, begin the migration. Follow these directives exactly:

Goal: do the migration. Validate that everything works correctly **before and after**.

- Run the api smoketest.
- Build the new kysely path off the `@deprecated` ServiceContext entirely — the
  endpoint/handler **and the services it owns** move to a kysely context. Use the
  TypeScript LSP to confirm the **new** path carries no `@deprecated` context usage.
  Do **not** delete the old `@deprecated` path in this PR: it is retained as the
  feature-flag fallback (step 3) and removed only when the flag is retired.
- Validate **all** endpoints. The smoketest harness only covers GET routes, so for
  every non-GET route use `curl` to capture before/after responses yourself. Keep
  the request payload body identical across before/after; metadata that legitimately
  changes (e.g. response timestamps) is fine.
- Migrate queries to kysely.
- The migrated view/RPC will be **dropped** post-migration, so define the builder's
  row type from the base-table builder (`InferResult`) or a hand-written schema —
  never infer it from the view's/RPC's generated `Selectable` type (duplicating the
  shape is expected and correct).
- **Consult version-correct docs; don't migrate from memory.** Before writing or
  restructuring a builder — and whenever you hit a query-builder type error or are
  about to reach for a raw ``sql`` template tag or ``sql<T>`` — invoke the
  **`kysely-docs` skill** (it reads this repo's pinned Kysely 0.28.x source, not model
  memory). For any *other* library you must reason about during the migration (pg,
  zod, nitro, date libs, …), invoke the **`docs` skill** (`$docs` — devkit's
  ``docm``-backed, version-correct source lookup) rather than recalling its API. Read
  `apps/api/docs/` for house style.
- **Types must be inferred, not asserted — this is the cleanup goal, not a nicety.**
  Express the query in the builder (`selectFrom`$joins/`jsonArrayFrom`/`jsonObjectFrom`/
  CTEs/`$narrowType`) so the row type falls out of the query. Eliminate
  `$castTo<…>()`, `.as()`-driven coercions, and `as SomeRow`/`as X` on builder output
  wherever the builder can infer the shape; a raw ``sql``/``sql<T>`` is a last resort,
  allowed only when there is genuinely no builder equivalent (confirm via
  `kysely-docs` first). A cast survives only where inference is truly impossible, in
  its narrowest safe form, justified in a one-line comment **and** in the PR body.
  `as any`, `as unknown as T`, `@ts-ignore`/`@ts-expect-error`, and non-null `!`
  remain banned outright (this restates and sharpens "no type smuggling via
  `unknown`" below).
- **Prove it before opening the PR.** `git diff origin/staging...HEAD` and grep the
  changed query paths for new `$castTo`, ` as ` casts on builder output, and
  ``sql``/``sql<`` usages. In the PR's validation section, either state "no asserted
  types introduced on query paths" or list each remaining assertion with the reason
  inference was impossible. An endpoint functionally on Kysely but still asserting its
  result types is **not** done.
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
- Ship the new path behind a feature flag — see step 3.
- Add the migration test battery — see step 4.

### 3. Ship the migrated path behind a feature flag (safety switch)

The kysely path goes to prod **behind a boolean flag that defaults to the old path**.
The point is an instant, no-deploy rollback: if the new path misbehaves in prod — a
divergence the local battery didn't surface, an RLS or scale regression, a
serialization edge — you flip the flag **off**, the endpoint falls straight back to
the proven old path, and you patch the new version and re-enable at your own pace.
That safety switch only exists if the old path is still there to fall back to, which
is why step 2 keeps it rather than deleting it.

`apps/api/docs/07.feature-flags.md` is the source of truth — **read it** before wiring
anything. The shape:

- **Create the flag** in PostHog (project `apps-api`, EU) via the PostHog MCP,
  **disabled by default**, named `<slug>-dbi-<NNNN>-<YYYY-MM-DD>` (descriptive slug +
  driving issue id + creation date, e.g. `results-create-dbi-10450-2026-07-15`).
- **Register it** in the `FLAGS` map in `server/utils/flags/index.ts`, pairing the
  PostHog `key` with its `envOverride` (uppercased slug + issue) so CI and local dev —
  where PostHog is usually absent — can pin the value deterministically.
- **Gate the route** on `getFlag(event, FLAGS.x, false)`. The default is **`false` =
  the old path**, so the endpoint serves the proven behaviour until the flag is
  deliberately turned on. The default value must always be the safe, old-path
  behaviour; `getFlag` never throws, so a flag can't itself break a request.
- **Keep both paths side by side.** Follow the doc's split pattern: put the new
  kyselyfied service/handler in a `_migration2026`-suffixed sibling, branch on the flag
  in the route, and right before merge rename the old file with an `_old` suffix. For a
  small swap an inline `if (await getFlag(...)) return newFn(...); return oldFn(...);`
  between two service functions is enough — the mechanic scales to the size of the
  change. Either way the old `@deprecated`-context path stays as the off-branch and is
  deleted later, in the flag-retirement cleanup (`docs/llm-guides/principles.md`: a
  retired flag is removed from code, not left toggled off).
- **Prove the switch works**, don't assume it. The HTTP E2E suite (step 4) asserts the
  resolved value in the wide event under `featureFlag.<key>` and exercises **both** the
  flag-on (new) and flag-off (old) branch — pin each with the `envOverride` — so the
  fallback is tested end to end.

Carve-out: if there is genuinely no distinct old path to fall back to — a pure
type-safety or relocation refactor whose SQL is parity-proven identical and whose
"old" path was already kysely (e.g. SWE-10450) — there are not two behaviours to gate,
so skip the flag. The flag is for a migration that introduces a **new, potentially
divergent** path, which is the common case.

### 4. Add the migration test battery

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
- When the migration ships behind a feature flag (step 3): run the auth + behaviour
  contract with the flag **on** (new path) and assert the fallback with the flag
  **off** (old path), pinning each via the `envOverride`, and assert the resolved
  value surfaces in the wide event under `featureFlag.<key>`. This proves the safety
  switch actually toggles paths.

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

> The `$issue-start` "orient only, don't edit code" rule is overridden here — this
> command's purpose is to carry out the migration once the workspace is confirmed.
