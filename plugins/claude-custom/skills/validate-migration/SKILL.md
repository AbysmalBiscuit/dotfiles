---
name: validate-migration
description: "Run validation after migrating endpoint to kysely. Use when the user invokes $validate-migration or asks for this workflow."
---

# $validate-migration

Before starting, invoke the **`checklist` skill** and create one task per bullet/validation step.

Make sure each of the following validation criteria are met:

- make sure to validate everything works correctly with before and after.
run the api smoketest.

- make sure that the `@deprecated` ServiceContext is removed and replaced with a kysely one in this endpoint/handler and the services it owns.
use the typescript lsp to make sure that you didn't accidentally miss any @deprecated context usage here.

- make sure you validate all endpoints. the smoketest harness only covers GET routes, so you will need to use curl to validate before/after for others yourself. when using curl, make sure that the payload body is the same (metadata like response timestamps changing is fine).

- make sure to run the entire test suite for the entire project.

- make sure to run the migration-specific test suites (integration/unit).

- make sure to migrate queries to kysely

- you are not allowed to change the withAdminDB helper. you can add new reasons for bypassing using withAdminDB, but you cannot change the helper itself. You cannot add any new helpers.

- you are not allowed to add new AuthContexts, you must use one of the existing ones.

- do not use `BaseContext` as a type outside of the `kysely.ts` file.

- when rpcs are used, migrate them to parametrized kysely queries. we want to fully use the type checker.

- use the adaptyv mcp when necessary

- no type smuggling — casts that bypass the checker instead of fixing the types.
  Scan the migrated handler + the services it owns with the structural checker:

  ```bash
  find-type-smuggling <changed file(s) or dir>
  ```

  It flags `x as unknown as T`, `x as any` (incl. `as any as T`), and `<any>x`/`<unknown>x`,
  and exits non-zero if any remain. A bare `x as unknown` is fine (unusable until narrowed).
  Also catch the comment-based escapes it can't see — `rg -n "@ts-(ignore|expect-error|nocheck)" <paths>`.
  Anything it finds in your migrated code must be removed: use parametrized kysely queries so
  the type checker validates the shape, not a cast.

- don't make constants for grouping column names. just inline them so the queries are easier to read
