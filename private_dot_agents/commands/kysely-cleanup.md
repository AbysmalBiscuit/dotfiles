---
description: Use when a kysely-migration PR's implementation is finished and you want to clean it up, validate it (including flag-gated TDD), and hand it off for review. [kc]
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, Skill, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__plugin_posthog_posthog__exec
---

For all these tasks use the `/checklist` skill.

## Delegation policy

Steps **5**, **6**, and **9** run as subagents; everything else runs in the main thread.

- **Steps 2, 3 and 7 stay in the main thread** — they edit the same files and depend on
  having the whole diff in view. Concurrent agents editing one handler clobber each other.
- **Step 4 stays in the main thread** — `/receiving-code-review` requires pushing back on
  reviewers and asking *me* when something is unclear. A subagent can't do either.
- **Step 9 must be a subagent that did NOT write the step-7 tests.** Whoever wrote them has
  a motive to accept a compile-error RED and call it validated. Separating the writer from
  the validator is the entire point; a fresh agent is the only way to get it.
- **Every subagent returns evidence, not a verdict.** "Validated, all green" is worse than
  no delegation at all, because it can't be audited. Reject any report whose claims aren't
  backed by the specific artifacts named in the step (`file:line`, the failing assertion
  text, the log line). Re-run it yourself if the evidence is missing.

Check this PR's diff and do the following:

1. if behind staging: rebase on latest staging.
2. Don't use ternaries for feature flags. Follow the example from the docs. If necessary, you can make bigger if blocks since cleaning this up in a follow-up pr will be easier this way.
3. use `/docs` skill like this:
```
/docs kysely check all kysely queries edited by this file. use builder instead of $castTo and sql<>`` literals. Also cleanup the `Kysely<ExtendedDB> | Transaction<ExtendedDB>` type annotations. Transaction extends Kysely, so doing the `|` doesn't add anything; it can be just `Kysely<ExtendedDB>`. Note: we are migrating all views and RPCs to kysely. NEVER type anything using views from the DB, as they will be removed. You will need to create new interfaces/zod schemas as you go along.
```
   **In non-test code, never annotate anything `unknown`** (query modules, services,
   endpoints, utils). First search the edited module and the `@adaptyv/db-types`
   kysely type modules for a type that already fits. If none exists, add the missing
   type so the value is properly typed (a zod schema + inferred row type, a
   `Selectable`/`Insertable<…>`, or a `ColumnOverrides` entry) — `unknown` is not an
   escape hatch for dodging Kysely inference. Only if you genuinely cannot avoid it,
   explain why and use the `ask` skill to ask me how to proceed; never silently ship
   it. Tests are exempt: `unknown` is fine where it's the right tool (a caught
   `error: unknown`, narrowing a parsed HTTP response) — but even in tests, don't
   `as unknown as X` to fabricate a typed value.

   **Done-gate: verify the mechanical cleanup with the ast-grep checker before
   moving on.** It structurally scans the changed files (comments and strings that
   merely mention these do NOT match) for the exact leftovers this step and step 2
   target: raw ``sql`` `` / ``sql<T>`` `` literals, `$castTo`, `Kysely<…> |
   Transaction<…>` unions, `unknown` annotations, `as any` / `as unknown` casts,
   and feature-flag ternaries.

   ```bash
   ~/Git/adaptyv/ast-grep/check.sh            # human summary of findings vs origin/staging
   ~/Git/adaptyv/ast-grep/check.sh --json     # machine-readable list to work through
   ~/Git/adaptyv/ast-grep/check.sh --added-only   # only lines this branch introduced
   ```

   Every finding is a blocking checklist item — this step is NOT done while any
   remain untriaged. For each, exactly one of: convert the query to a builder / fix
   the type / turn the flag ternary into an if block; OR, only if you genuinely
   cannot, keep it and record the specific `$KYSELY/src/…:line` you opened that
   proves no builder exists. "Looked fine" is not a resolution. Scan the whole
   changed file (default) to also catch pre-existing literals in a query you
   edited; use `--added-only` when you only want the lines this branch added.
4. use `/receiving-code-review`:
```
/receiving-code-review pull pr comments. address anything that is still an issue. then reply inline to comments. ask me if you have any doubts or anything is unclear or you need extra context.
```
5. check that any feature flags added in pr exist on posthog. If the flags are missing, create them.

   **Subagent (read-only).** Dispatch one agent with the list of flag keys the diff
   introduces. It looks each one up on posthog and returns, per key: `EXISTS` (with the
   flag's posthog key and current rollout) or `MISSING`. It does not create anything —
   creating a flag is a write on a shared system, so you do that yourself in the main
   thread from the returned `MISSING` list.
6. if this pr adds new interfaces/zod schemas etc. that don't draw on existing table definitions (eg, when porting a view or rpc), check via adaptyv mcp that the interfaces/zod schemas type things in a way that matches the DB, and that the kysely queries match it.

   **Subagent (read-only).** Dispatch one agent with the list of new interfaces/schemas and
   the queries that produce them. It queries the DB through the adaptyv mcp and returns one
   row per field: field name, the declared TS/zod type, the actual DB column type and
   nullability, and `MATCH` / `MISMATCH`. Nullability counts — a `z.string()` over a
   nullable column is a MISMATCH. Schema dumps stay in the subagent; only the table comes
   back. Apply every fix yourself in the main thread.
7. Add any missing HTTP e2e tests so the migrated path is properly covered —
   including the flag-on path. They must be real tests that follow the `/validate-tdd`
   rules: drive the actual endpoint over HTTP with a realistic payload through
   auth / validation / serialization, and assert user-observable behavior (the
   response AND the persisted state). No ceremony — no unit test that pins the one
   changed line and passes whether or not the migration works. The bar: each test
   must go RED if the migrated query/write is broken (you prove exactly that in step 9).
8. commit.
9. **Validate the tests with `/validate-tdd`'s RED-GREEN discipline** — revert the
   migrated fix → the step-7 tests go RED for the right reason (a behavioral
   assertion, not a compile error) → restore → GREEN. This needs a **running**
   server, not just a build — and if the migration is flag-gated, the new path only
   executes when the flag is on, so validate under BOTH flag states. (Run the steps
   here directly; the bare `/validate-tdd` command doesn't know the server/flag setup.)

   **Run this as a subagent — a fresh one that did not write the step-7 tests.** Pass it the
   whole procedure below verbatim, plus the branch, the suite path, the flag env var, and
   which source change to revert for the RED check. It owns the server lifecycle end to end
   (build → serve → run → revert → rebuild → restore → tear down), so the build output,
   server logs and suite runs never enter the main thread. It edits only the one source
   change it reverts and restores — no other file, and no test file. If it finds the tests
   are wrong, it reports that; it does not fix them.

   Use the prod-mode server (fast, low-memory), NOT `devrun up api` (nitro dev is a
   debug build: slow + memory-hungry). Ports are auto-allocated by portm — always
   read the port back from `devrun status`, never hardcode.

   ```bash
   cd apps/api
   devrun task api-profile-build          # builds .output/server (NITRO_PRESET=node-server)
   devrun up api-serve                     # serve it — flag OFF
   PORT=$(devrun status | awk '$2=="api-serve"{print $1}')

   # Write/integration suites are [supabase:write]: need ALLOW_DB_WRITES + a staff
   # token + the DB client env, all from doppler dev_local. Run flag OFF (old path):
   doppler run -p api-foundry -c dev_local -- env API_BASE=http://localhost:$PORT ALLOW_DB_WRITES=true \
     bun test tests/integration/http-auth/<suite>.integration.test.ts   # expect GREEN

   # Flag ON — the flag is read server-side at request time, so reboot with the override:
   devrun down api-serve && devrun up api-serve --env <FLAG_ENV>=true
   PORT=$(devrun status | awk '$2=="api-serve"{print $1}')
   doppler run -p api-foundry -c dev_local -- env API_BASE=http://localhost:$PORT ALLOW_DB_WRITES=true \
     bun test tests/integration/http-auth/<suite>.integration.test.ts   # expect GREEN
   ```

   Then CONFIRM the flag-on run actually hit the new code (not a silent fallback):
   grep the server log (`devrun logs api-serve`) for the migrated path's operation
   name and `"source":"env"` on the flag. If the log shows the old operation, the
   override didn't take — fix that before trusting the green.

   Decisive RED check (the point of validate-tdd): revert the migrated write in the
   source, `devrun task api-profile-build && devrun down api-serve && devrun up
   api-serve --env <FLAG_ENV>=true`, re-run the suite → it MUST fail on a *behavioral*
   assertion (persisted-row parity / links), not a compile error. Restore, rebuild,
   reboot, re-run → GREEN. Note: with the built server every source revert needs a
   rebuild, not just a reboot.

   Tear down when done: `devrun down api-serve`, and confirm the reverted source is restored
   (`git status` clean apart from the intended branch changes).

   **What the subagent returns.** Evidence, not a verdict — a report of "validated" with
   nothing under it is a failed run, and you re-do the step yourself:
   - the RED run: test name, the **assertion** that failed, and its verbatim
     expected/received output. A compile/import/type error is NOT a valid RED — report it as
     `INVALID RED` and stop, because it proves nothing about the migrated behavior.
   - the GREEN runs after restore, both flag states, with the pass counts.
   - the `devrun logs api-serve` line proving the flag-on run hit the migrated path — the
     new operation name and `"source":"env"`. Old operation name in the log means the
     override didn't take and the green is meaningless.
   - the exact commands it ran, in order, so the whole loop can be reproduced.
10. push.
11. if everything succeeds and there weren't any issues, run `/issue-review-kysely`
    command — it pushes and opens/reuses the PR without adding a reviewer or sending
    any Slack message. Do not fall back to `/issue-review` or `issue review request`
    here; nobody is being pinged for this cleanup.

