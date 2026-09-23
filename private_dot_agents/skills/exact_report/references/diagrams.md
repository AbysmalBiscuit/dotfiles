# Diagrams

Draw one whenever it carries the idea better than prose: any flow, architecture,
sequence, state machine, hierarchy, timeline, or relationship. A report about a
system, a process, or a multi-actor interaction gets at least one. Skip whatever
a single sentence already settles.

Mermaid renders client-side from a `<pre class="mermaid">` block plus the CDN
script the scaffold already includes. The source stays human-readable, so a
reader still sees the structure if the script fails to load.

## Pick the type

| Showing | Type |
|---------|------|
| Steps / pipeline / decision branches | `flowchart TD` (or `LR`) |
| Actors exchanging messages over time | `sequenceDiagram` |
| States and transitions | `stateDiagram-v2` |
| Tables / entities and relations | `erDiagram` |
| Class / module structure | `classDiagram` |
| Schedule / timeline / phases | `gantt` or `timeline` |
| Proportions of a whole | `pie` |

Usual fit per report kind:

- `overview`: flowchart or sequence of how it works; `erDiagram` for the data model.
- `investigation`: sequence of the failing interaction; flowchart of the trigger path.
- `decision`: flowchart of the decision itself; keep small comparisons as tables.
- `comparison`: the table leads; add a diagram only where structure differs.
- `status`: `gantt`/`timeline` for schedule; flowchart for the pipeline's current state.

## Make it readable

The content column is 960px. Anything past about four nodes, or with real label
text on them, gets scaled down to illegible at rest. Every item below is one line
of work, so do all of them every time.

- **`flowchart TD` beats `LR` for chains.** Five-plus nodes left-to-right get
  squeezed hard in 960px; top-down uses the page's infinite vertical space. Reach
  for `LR` only when the diagram is short or wide by nature. `sequenceDiagram` and
  `erDiagram` set their own orientation.
- **Every figure gets the expand button.** `<button class="zoom" type="button">⤢ Expand</button>`
  as the first child of `<figure class="diagram">`. The inlined script clones the
  rendered SVG into a fullscreen overlay with pan and zoom: scroll or `+`/`−` zooms
  about the cursor, drag or the arrows pan, `Fit` and `100%` reset, `Esc` closes.
  Fitting alone would not help, since a tall graph fitted to the viewport is as
  unreadable as it was inline. The transform scales an SVG, so labels stay sharp at
  any zoom.
- **Label every arrow.** A bare arrow cannot say whether it means "triggers",
  "creates", or "moves a pointer". `check` warns on unlabelled edges.
- **One idea per diagram.** Two small diagrams beat one tangled one.
- **Real names on the nodes**: functions, services, tables. Never `A → B`.
- **Load-bearing numbers on the diagram**, not only in the prose:
  `dna_sequence<br/><small>71,273 rows · 159 MB</small>`. Style the edge that
  carries the point so it reads at a glance: `linkStyle 5 stroke:#d29922,stroke-width:2px`.
  A diagram that restates the prose adds nothing; one that carries the argument
  earns its space.

## Legends go in HTML

Put a `<div class="dlegend">` inside the `<figure>`, after the `</pre>`. The
lightbox clones it into a fixed footer, so it survives expanding.

```html
<div class="dlegend"><b>Arrow colour</b><span><i style="background:#3fb950"></i>what it means</span></div>
```

A legend built as a mermaid `subgraph` has no edge into the main graph, so dagre
lays it out as a disconnected component parked beside the graph. That inflates the
bounding box, and the real content gets scaled down to share the width with a box
of static text. Anchoring the legend with an invisible `~~~` does work, but the
lexer returns `~~~` as a `LINK` like any visible arrow, so it takes a slot in the
array `linkStyle` indexes into and silently renumbers your coloured edges.
`check` fails on a legend subgraph.

## Group parallel work

A bare fan-out cannot say whether its branches run in sequence or at once. Wrap
simultaneous nodes and number the boxes in firing order:

```
subgraph W1["1 · <what triggered it> · these run in parallel"]
  ...
end
style W1 fill:none,stroke:#6e7681,stroke-dasharray:6 4,color:#e6edf3
```

## Validate, then look

Mermaid fails silently in the browser: a syntax error renders as a blank box or
raw source, and the file alone never tells you. An out-of-range `linkStyle` index
takes down the whole render, not just that edge, so re-count after adding or
removing any arrow.

`report.py check` puts every block through `mmdc` and reports the parse error.
Exit 0 means it renders, not that it reads:

```bash
~/.agents/skills/report/scripts/report.py render reports/<slug>.html
```

writes a PNG per diagram under `reports/.diagrams/`. Read them. A diagram parses
clean and is still an unreadable tangle, and that is the cheapest way to catch
overlapping nodes and overflowing labels.
