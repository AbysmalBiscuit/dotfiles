# What the graph models, and what it leaves out

Reach for this when a result came back empty and the emptiness has to be
explained, or when an edge has to be trusted or discounted.

**Measure, never quote.** Every count moves on rebuild, so no figure is written
down here. The session-start script prints this graph's own numbers.

## Four kinds of node

`file_type` separates them, and a query seeds across all four.

- **code**: functions, classes, files. What most questions are about.
- **document**: a file or a heading inside one, from markdown and papers.
- **rationale**: a docstring or comment, joined to the symbol it describes by
  `rationale_for`. A hit here is a hit on the prose, and the symbol is one hop
  away.
- **concept**: a term the semantic pass lifted out of the corpus. Some are real
  domain nouns; some are words like `boolean` or `null` scraped from a JSON
  schema, and those are exactly the nodes that turn a sentence-shaped query into
  a thousand-node sweep.

## EXTRACTED against INFERRED

`EXTRACTED` edges come from the AST: the parser saw the call, the import, the
definition. They are as reliable as the parse.

`INFERRED` edges come from the semantic pass, where an LLM read the file and
proposed a relationship. They carry real signal and they are guesses. An
`INFERRED` edge is a lead to verify in the source, never the evidence itself,
and `--mode deep` extraction produces many more of them.

## A label is not an identity

Matching is fuzzy and case-insensitive, so `deletePlate()` and `DeletePlate()`
collapse, and a method name repeated across five classes is five nodes with one
label. `explain` picks one and prints its `ID:`; `affected` refuses. Neither
tells you a duplicate existed. When a symbol's name is common, check the
`Source:` line names the file you meant before building an answer on it.

Community names are LLM-generated, so a `community=Plate Selection UI` tag is a
real topic name and worth reading as one.

## The boundaries it does not cross

Every edge comes from one file's syntax, so a relationship that only exists at
runtime has no edge:

- **Across the network.** An HTTP call site and the route handler serving it are
  unconnected nodes. So are an RPC caller and its remote function.
- **Across storage.** A query call site and the table it reads are unconnected,
  even when the graph was built with `--postgres` and holds both.
- **Through dynamic dispatch.** A handler reached by a name assembled at
  runtime, a registry lookup, or a string key is invisible to the parser.

Those traces are source searches. Run them as such, and say so in the answer
rather than reporting "nothing calls it".

## What was never indexed

Extraction respects `.gitignore` and `.graphifyignore` unless the build passed
`--no-gitignore`, and a `--code-only` build has no document, rationale, or
concept nodes at all. A file absent from the graph may simply have been out of
scope, which is a different claim from the code not containing it.

## Directed traversal over an undirected file

`graph.json` usually records `directed: false` while `path` still walks edges
forwards by default. That is why a caller-to-callee path resolves and its
reverse reports `No directed path found`. `--undirected` is the retry, not a
sign of a broken graph.
