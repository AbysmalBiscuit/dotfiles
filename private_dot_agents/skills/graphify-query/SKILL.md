---
name: graphify-query-gq
description: "Query an existing graphify graph, and do it before searching files by hand: where something lives, what calls what, what a symbol is for, what breaks if it changes, how one symbol reaches another, which hubs hold the project together, the code behind an error message. Building or rebuilding a graph is the graphify skill's job."
argument-hint: "Question, symbol, bug description"
allowed-tools: Bash(graphify:*), Bash(bash:*), Bash(rg:*), Read
---

# Querying a graphify graph

`graphify` queries a knowledge graph of a project: files, symbols, documents,
and the docstrings that describe them as nodes, joined by what calls, contains,
imports, and references what. Every edge comes from one file's syntax, so the
graph answers questions about the code as written, and stops at the boundaries
that only exist at runtime.

## Open the session

Run `scripts/start.sh` from this skill's own directory, the base directory named
where this skill was loaded from. It prints which graph answers queries here,
what it holds, how many commits and files the code has moved past the build, and
what earlier sessions recorded: nodes worth starting from, dead ends not worth
re-deriving.

## Seed on a symbol, never a sentence

`query` matches the words you pass against node **labels**, so a sentence seeds
on every ordinary word in it:

```bash
graphify query "how does the config file get read"
# seeds on Config, config_file(), File structure, README.md: 115 unrelated nodes
graphify query "load_config()"
# seeds on load_config(): the module that reads it and its callers
```

The first line of the output is the diagnostic. It names the seeds it chose, any
context filter it applied, and the node count:

```
Graph: graphify-out/graph.json (1005 nodes) | Traversal: BFS depth=2 | Start: ['load_config()', 'Config'] | Context: call (heuristic) | 75 nodes found
```

`(heuristic)` means a word in your question, `calls` or `imports` or `returns`,
narrowed the graph to that edge context on its own. Often what you wanted. Pass
`--context call` to choose it deliberately, or drop the word to search
everything. A truncation warning names how many nodes were cut: raise `--budget`
or seed narrower rather than reading the surviving sample as the answer.

Labels are literal, and worth copying out of the output rather than typing: a
function keeps its parens (`load_config()`), a file is its name (`update.py`), a
document section is its heading.

Matching is fuzzy and case-insensitive, so `deletePlate()` collides with
`DeletePlate()`, and a method name repeated across classes is many nodes with
one label. `explain` picks one silently and prints the `ID:` line naming which;
`affected` refuses both with `No unique node match`. Pass the ID that `explain`
printed to name one of them.

## Pick the verb that matches the question

| Question | Command |
| --- | --- |
| What surrounds X? | `graphify query "<symbol>"` (`--budget 5000` breadth, `--dfs` one path) |
| What is X, what touches it? | `graphify explain "<label>"` |
| How does A reach B? Trace a flow. | `graphify path "<A>" "<B>"` (`--undirected` on an empty answer) |
| What breaks if I change X? | `graphify affected "<label>" --depth 2` (1 on a hub) |
| Where do I start in an unfamiliar repo? | `graphify god-nodes --top 20` |
| Where does this error come from? | `graphify query "<an identifier from the trace>"` |

A `path` result names every hop and the relation carrying it. Direction is part
of the answer: the search walks edges forwards, so caller to callee resolves
while the reverse reports `No directed path found`. `--undirected` finds it and
marks each hop's true direction.

```
load_config() <--imports [EXTRACTED]-- update.py --contains [EXTRACTED]--> run_update()
```

`affected` walks every dependency relation by default, which on a shared module
is mostly test files. `--relation calls` and a `rg -v` for test paths cut it back
to what would break at runtime.

An error message is not a node label, and querying its text seeds on ordinary
words. Take an identifier out of the trace instead: a frame's function, the file
in the top frame, or the constant the message is defined in.

`explain` prints a `Lesson:` line when an earlier session recorded one about that
node. `query` does not, which is why the session opens by reading LESSONS.md.

## Say which kind of empty you got

A finished answer names its nodes and the hops between them, so the reader can
re-run it: `run_update()` calls `resolve_config()`, which calls `load_config()`
in `bridge/config.py`.

An empty result is a weaker claim than it looks, and only one of its causes is
about the code.

**The graph is behind.** It holds what was extracted, as of the commit
`start.sh` named. A file written since the build is absent from the graph and
present in the code.

**The path was never indexed.** Extraction respects `.gitignore` and
`.graphifyignore`, and a `--code-only` build carries no documents at all.

**The edge crosses a boundary graphify does not model.** An HTTP call site and
the route serving it are separate nodes with nothing between them, and so are a
query call site and its table. A handler reached through a runtime-assembled
name is invisible for the same reason.

Searching the source for a route path or a table name is the correct move for
the third case. Report it as the source search it was, rather than reporting
"nothing calls this" when the truth is that the graph models no such call.

## Record the answer

```bash
graphify save-result --question "<one line: what was asked>" --answer "<the answer>" \
  --nodes "load_config()" --outcome useful   # or dead_end, or corrected
graphify reflect --graph graphify-out/graph.json   # fold it into LESSONS.md
```

<critical>
`--nodes` takes labels copied verbatim from query output. A hand-typed name
matches no node and is dropped in silence, leaving a memory that teaches nothing.
</critical>

Summarise the question in one line: it is stored verbatim and shown to every
later session, so a pasted stack trace buries the lessons around it. `corrected`
also takes `--correction "<what was right>"`. Record the dead ends, since a
phrasing that returned noise is what the next session most needs to skip, and
these results are the only thing the lessons are built from.

## Reference

- [`references/verbs.md`](references/verbs.md) - every flag that changes what a verb returns, the relation set `affected` walks, querying a different or cross-repo graph.
- [`references/limits.md`](references/limits.md) - the four kinds of node, INFERRED against EXTRACTED, what the graph leaves out.
- [`references/freshness.md`](references/freshness.md) - which rebuild command refreshes which layer, which need an API key, the git hooks that do it for you.
