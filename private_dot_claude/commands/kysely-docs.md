---
description: Answer a Kysely question by searching the local kysely checkout — docs first, source when the docs fall short
allowed-tools: Bash, Read, Glob, Grep, Agent
argument-hint: "<question or topic> (e.g. \"how do I do a left join with a subquery\")"
---

# /kysely-docs

Answer this Kysely question using the local checkout at `~/Git/github/kysely`:

**$ARGUMENTS**

The point is to answer from what Kysely's code and docs *actually* say at the version
on disk, not from memory of the library — its API has churned across versions, so a
recalled answer is a guess. Ground every claim in a file you read.

## Where to look

| Source | Path | What's there |
|---|---|---|
| Prose docs | `~/Git/github/kysely/site/docs/` | Getting started, migrations, dialects, plugins, recipes, examples |
| Source + TSDoc | `~/Git/github/kysely/src/` | The real API. Method TSDoc carries runnable examples and the compiled SQL |
| Tests | `~/Git/github/kysely/test/` | Behavior at the edges, and the exact SQL each builder emits |
| Example app | `~/Git/github/kysely/example/` | An end-to-end wiring of the library |

Kysely's TSDoc is unusually good — most query-builder methods document their example
usage *and* the SQL they compile to. When the prose docs are thin, the method's TSDoc
in `src/query-builder/` is usually the better answer, not a fallback.

## How to search

First expand what the user gave you. A terse topic like "jsonb" or "cte" should become
the set of terms Kysely actually uses in its code: type names, method names, and the
SQL keyword. `cte` → `with`, `withRecursive`, `CommonTableExpression`. `upsert` →
`onConflict`, `doUpdateSet`, `onDuplicateKeyUpdate`. Searching the user's word alone
tends to miss, because the library names things after its own builder API.

Then:

1. `rg -i "<terms>" ~/Git/github/kysely/site/docs/` — prose first, it's written for humans
2. `rg -i "<terms>" ~/Git/github/kysely/src/` — TSDoc examples and the actual signatures
3. `rg -i "<terms>" ~/Git/github/kysely/test/` — only when you need to confirm emitted SQL or an edge case

Read the files the search points at rather than trusting the matching line in isolation;
a method signature means little without the surrounding types.

For a broad question that spans several subsystems (dialects × a feature, say), fan the
searches out to parallel `Explore` agents and synthesize — but for anything narrow, just
search directly. Spawning an agent to grep one directory is slower than grepping it.

## Answering

Lead with the answer: the code the user should write. Then a short explanation of why it
works, and cite the files you drew it from as `path:line` so they can read further.

If the docs and the source disagree, the source wins — say so explicitly, since it means
the docs are stale at this version. If the checkout genuinely doesn't cover the question,
say that rather than filling the gap from memory; offer what the nearest supported
approach is.
