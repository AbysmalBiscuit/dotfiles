# The read verbs, flag by flag

Reach for this when a verb's default answer is the wrong shape: too broad, too
narrow, filtered by something you did not ask for, or aimed at the wrong graph.

Every verb takes `--graph <path>`, so one checkout can query another project's
graph, or the cross-repo one at `$(graphify global path)` once repos have been
added to it with `graphify global add`.

## query

BFS from the seeds it matched, to depth 2, rendered until a token budget runs
out.

| Flag | Effect |
| --- | --- |
| `--budget N` | token cap, default 2000. The truncation line names how many nodes were cut. |
| `--dfs` | depth-first, so the output follows one chain instead of a ring of neighbours |
| `--context C` | keep only edges of that context, repeatable |

Context names are normalised before they filter, and the header line echoes the
name that survived. `--context decorator` reports `Context: attribute` and
matches nothing, because the alias table renames it while the graph still
stores `decorator`. Read the contexts your graph actually carries rather than
guessing one:

```bash
python3 -c "import json,collections;g=json.load(open('graphify-out/graph.json'));print(collections.Counter(l.get('context') for l in g['links']).most_common())"
```

`call`, `import`, `parameter_type` and `return_type` survive normalisation
unchanged and cover most questions. Many edges carry no context at all and drop
out under any filter, so a filter can cut further than it reads.

When you pass none, the question's own words can still pick one: a query
containing `calls`, `imports`, `returns`, `fields`, `parameters` or `generics`
infers that context and the header reports it as `(heuristic)`.

## explain

One node's identity and every edge on it. No flags beyond `--graph`.

```
Node: update.py
  ID:        bridge_update
  Source:    bridge/update.py L1
  Community: update.py
  Degree:    40

Connections (40):
  <-- cli.py [imports_from] [EXTRACTED] bridge/cli.py:L15
  --> run_update() [contains] [EXTRACTED] bridge/update.py:L684
```

`<--` is an edge into this node, so the callers of a function are the `<--
[calls]` rows. `-->` is what it reaches. The bracketed file and line belong to
the edge, not the node: they say where the call was written.

## path

Shortest path between two nodes, matched fuzzily. A `warning: source match was
ambiguous` line with two scores means it guessed, so check the endpoints it
printed. `--undirected` searches ignoring edge direction and marks each hop's
real direction in the output.

## affected

Reverse traversal: who depends on this node, `--depth` hops back, default 2.
Start at 1 on a hub or the answer drowns.

`--relation R` replaces the default walk, repeatable. The default set prints in
the output header, and covers `calls`, `indirect_call`, `references`, `imports`,
`imports_from`, `dynamic_import`, `re_exports`, `inherits`, `extends`,
`implements`, `uses`, `mixes_in`, `embeds`, `requires`. `--relation calls` alone
answers "what would break at runtime" far more directly than the default, which
counts every test file that imports the module.

There is no test filter. Test callers usually outnumber real ones, so cut them
at the shell when the question is about production impact:

```bash
graphify affected "load_config()" --depth 1 | rg -v '(^|/)tests?/'
```

`affected` takes a node ID as readily as a label, which is the way past `No
unique node match`.

## god-nodes

`--top N` most-connected nodes, `--json` for machine output. The fastest
orientation in an unfamiliar repo: the hubs are where its control flow gathers.

## diagnose multigraph

Counts how many edges collapse onto the same node pair, alongside dangling
endpoints, self loops and exact duplicates. A `same_endpoint_group_count` above
zero is why an `explain` row can show one relation where the extraction found
several. Run it before quoting an edge count as a fact.
