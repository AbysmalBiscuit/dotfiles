# Keeping the graph current

Reach for this when the session-start script reported the code has moved past
the build, or when a rebuild has to refresh a specific layer.

## Which command refreshes which layer

```bash
graphify update .            # changed code files, AST only, no API key
graphify update . --force    # same, and accept a graph with fewer nodes than before
graphify extract .           # everything: AST plus the semantic pass over docs and papers
graphify extract . --code-only   # everything code, still no API key
graphify cluster-only .      # recluster an existing graph, no re-extraction
graphify label .             # rename communities with the configured LLM
```

`update` is the one to reach for. It re-extracts only the code files that
changed and needs no backend, so it costs seconds and no tokens. It leaves the
document, rationale, and concept layers exactly as they were, which is correct
after a code change and wrong after a docs rewrite.

`update` refuses to write a graph smaller than the one on disk, on the
assumption that a shrinking rebuild is a broken one. After a refactor that
genuinely deleted code, that guard is the thing standing between you and a
current graph: pass `--force`.

`extract` runs the semantic pass, so it wants `GEMINI_API_KEY`,
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or a local server through
`OPENAI_BASE_URL`. `--mode deep` spends more of that budget on INFERRED edges.
Two flags widen what a build sees beyond source files: `--postgres DSN` maps a
live schema's tables, views, and functions into the graph, and `--cargo` adds
crate-to-crate dependencies.

**A Postgres DSN passed here points at a local development database. Never a
remote or production one.**

## Let commits do it

```bash
graphify hook install     # post-commit and post-checkout rebuilds, plus a graph.json merge driver
graphify hook status      # what is installed in this repo
```

The merge driver matters on a shared branch: `graph.json` conflicts on almost
every merge otherwise, and the driver union-merges the two sides instead.

Without the hooks, nothing rebuilds on its own, and the session-start script's
commit count is the only warning you get.

## Lessons follow the graph

`save-result` writes one memory file per answer under `graphify-out/memory/`.
`reflect` folds them into `graphify-out/reflections/LESSONS.md` and a sidecar
that `explain` reads:

```bash
graphify reflect --graph graphify-out/graph.json
```

It is deterministic and LLM-free, so it costs no tokens. Run it after saving a
result mid-session, or the lesson stays invisible until someone else does.

Reflection hashes each cited node's source file, so a lesson about code that has
since changed is marked stale rather than dropped. A node needs two distinct
useful results before it is promoted from tentative to preferred, and signals
halve every 30 days, so the lessons shed themselves without pruning.
