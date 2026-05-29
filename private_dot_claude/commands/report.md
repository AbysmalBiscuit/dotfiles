---
description: Generate a standardized self-contained HTML report under reports/ for summarizing and giving context about anything
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# /report

Generate a self-contained HTML report in `reports/` for summarizing information
and giving context about a topic: a system, an investigation, a decision, a
comparison, a status update, an audit. Every report uses the same theme,
components, and structure so they read as one series.

This is the generic sibling of `/pr-review-report`. Use that one for PR/security
reviews; use this for everything else.

## Inputs

Ask the user for any missing item. Keep it short — infer sensible defaults and
confirm rather than interrogating.

1. **Topic / title** (short noun phrase, e.g. `Auth token refresh flow`,
   `Q2 ingestion pipeline status`).
2. **Purpose** — one line: what question does this report answer, for whom?
3. **Report kind** — one of:
   - `overview` — explain how something works / orient a reader
   - `investigation` — what happened, evidence, root cause
   - `decision` — options weighed, recommendation
   - `comparison` — N things across shared dimensions
   - `status` — current state, progress, risks, next steps
4. **Tag** (optional) — short status word for the top pill (e.g. `DRAFT`,
   `FINAL`, `FYI`, `ACTION NEEDED`, `INFO`).
5. **Sources** — files, commands, links, or data the report draws on.

## Output

- Path: `reports/<kebab-slug>.html`
- Slug rules: lowercase, dashes, no dates, no numeric prefix. E.g.
  `auth-token-refresh-flow.html`, `ingestion-pipeline-status.html`.
- One self-contained HTML file. CSS inlined. Only allowed external asset: the
  Mermaid script from CDN (for diagrams). Everything else inlined.

## Workflow

1. Gather context: read the named files, run the named commands, fetch the
   links. Collect concrete facts — paths, numbers, dates, quotes.
2. Verify when possible. If a claim can be checked (run a command, count rows,
   read the code), check it and cite the result verbatim.
3. Draw a diagram whenever it carries the idea better than prose: any flow,
   architecture, sequence, state machine, hierarchy, timeline, or relationship.
   Use Mermaid (see "Diagrams" below). A report with a system, process, or
   multi-actor interaction should have at least one diagram.
4. Pick the section set for the report kind (see below). Drop any section with
   no content — never leave a placeholder heading.
5. Write to `reports/<slug>.html`.
6. Print the path and a one-line summary to the user.

## Section sets by kind

Section 0 (pill + H1 + subtitle), 1 (meta grid), 2 (TL;DR), and the footer are
**always present**. The rest vary:

| Kind | Body sections (in order) |
|------|--------------------------|
| `overview` | How it works · Key components (table) · Data/flow · Gotchas · Pointers |
| `investigation` | What happened · Evidence (tables/repro) · Root cause · Impact · Fix / next steps |
| `decision` | Context · Options (A/B/…) · Trade-offs (table) · Recommendation · Risks |
| `comparison` | Comparison table (lead) · Per-item notes · Verdict |
| `status` | Current state · Progress (table) · Risks/blockers · Next steps |

Number body sections with a middle dot: `## 1 · How it works`.

## Diagrams

Draw a diagram whenever it explains faster than prose. Use Mermaid — it renders
client-side from a `<pre class="mermaid">` block plus one CDN script (already in
the skeleton). The source stays human-readable, so if the script fails to load
the reader still sees the diagram text.

Pick the diagram type by what you're showing:

| Showing | Mermaid type |
|---------|--------------|
| Steps / pipeline / decision branches | `flowchart LR` or `flowchart TD` |
| Actors exchanging messages over time | `sequenceDiagram` |
| States and transitions | `stateDiagram-v2` |
| Tables / entities and relations | `erDiagram` |
| Class / module structure | `classDiagram` |
| Schedule / timeline / phases | `gantt` or `timeline` |
| Proportions of a whole | `pie` |

Per kind, the usual fit:

- `overview` → flowchart or sequence of how it works; erDiagram for data model.
- `investigation` → sequence of the failing interaction; flowchart of the trigger path.
- `decision` → flowchart of the decision, or a small comparison still as a table.
- `comparison` → keep the lead a table; add a diagram only if structure differs.
- `status` → gantt/timeline for schedule; flowchart for the pipeline's current state.

Rules:

- Wrap every diagram in `<figure class="diagram">` with a `<figcaption>`.
- Keep nodes labelled with real names (functions, services, tables), not generic
  `A → B`.
- One idea per diagram. Two small diagrams beat one tangled one.
- Don't diagram what a one-line sentence already settles.

## Voice + prose rules

- **Active voice.** "The worker retries failed jobs." Not "Failed jobs are
  retried."
- **Concrete and definite.** Real paths, real numbers, real quotes. Cite verbatim:
  `exit code 137 (OOM)`.
- **Positive form.** "Runs in 200ms" not "does not take long."
- **Omit needless words.** Cut `actually`, `simply`, `basically`, `just`,
  `clearly`, `it should be noted that`.
- **No em-dashes (—) in prose.** Use period, comma, parens, or restructure.
  Em-dashes inside code samples are fine.
- **Section headings use a middle dot for numbering.** `## 1 · How it works`.
- **Heading nouns specific.** "Ingestion retries" beats "Details."
- **One tense per section.** Past for what happened, present for current state.

## HTML skeleton

Copy this verbatim. Replace placeholders inside `{{double-braces}}` only. Add or
drop `<h2>` body sections to match the chosen kind.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>{{Report title — short}}</title>
<style>
  :root{
    --bg:#0d1117; --panel:#161b22; --panel2:#1c2230; --border:#30363d;
    --fg:#e6edf3; --muted:#9da7b3; --accent:#58a6ff; --warn:#d29922;
    --bad:#f85149; --good:#3fb950; --code:#1f2530;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--fg);
    font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;}
  .wrap{max-width:960px;margin:0 auto;padding:40px 24px 96px}
  h1{font-size:28px;line-height:1.25;margin:0 0 4px}
  h2{font-size:20px;margin:40px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--border)}
  h3{font-size:16px;margin:24px 0 8px;color:var(--accent)}
  p{margin:10px 0}
  code,pre{font-family:"SF Mono","JetBrains Mono",Menlo,Consolas,monospace}
  code{background:var(--code);padding:1px 6px;border-radius:5px;font-size:13px}
  pre{background:var(--code);border:1px solid var(--border);border-radius:8px;
    padding:14px 16px;overflow:auto;font-size:13px;margin:12px 0}
  .meta{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;
    background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:16px;margin:20px 0}
  .meta div{font-size:13px}
  .meta .k{color:var(--muted);text-transform:uppercase;letter-spacing:.04em;font-size:11px}
  .meta .v{font-weight:600;margin-top:2px}
  .pill{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:.02em}
  .pill.tag{background:#0d2336;color:var(--accent);border:1px solid #1a3a5a}
  .pill.tag.warn{background:#3b2300;color:var(--warn);border-color:#5a3a00}
  .pill.tag.bad{background:#3a0d0d;color:var(--bad);border-color:#5a1717}
  .pill.tag.good{background:#0f2e16;color:var(--good);border-color:#1b5e2a}
  .callout{border-left:4px solid var(--accent);background:var(--panel);
    border-radius:0 10px 10px 0;padding:14px 18px;margin:18px 0}
  .callout.bad{border-left-color:var(--bad)}
  .callout.good{border-left-color:var(--good)}
  .callout.warn{border-left-color:var(--warn)}
  .callout strong{display:block;margin-bottom:4px}
  table{border-collapse:collapse;width:100%;margin:14px 0;font-size:13px}
  th,td{border:1px solid var(--border);padding:8px 10px;text-align:left;vertical-align:top}
  th{background:var(--panel2);font-weight:600}
  td.num{font-variant-numeric:tabular-nums}
  .del{color:var(--bad)} .add{color:var(--good)}
  .diff .hdr{color:var(--muted)}
  .muted{color:var(--muted)}
  ol,ul{margin:10px 0;padding-left:24px} li{margin:6px 0}
  footer{margin-top:64px;padding-top:16px;border-top:1px solid var(--border);color:var(--muted);font-size:12px}
  .flow{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:16px;margin:14px 0;font-size:13px}
  .flow .n{color:var(--accent);font-weight:700}
  kbd{background:var(--panel2);border:1px solid var(--border);border-bottom-width:2px;border-radius:5px;padding:1px 6px;font-size:12px}
  details.code{border:1px solid var(--border);border-radius:10px;margin:18px 0;background:var(--panel);overflow:hidden}
  details.code>summary{cursor:pointer;padding:13px 16px;font-weight:600;color:var(--accent);list-style:none;user-select:none}
  details.code>summary::-webkit-details-marker{display:none}
  details.code>summary::before{content:"▸  ";color:var(--muted)}
  details.code[open]>summary{border-bottom:1px solid var(--border)}
  details.code[open]>summary::before{content:"▾  "}
  details.code .body{padding:4px 18px 14px}
  details.code .body h3:first-child{margin-top:14px}
  figure.diagram{margin:18px 0;background:var(--panel);border:1px solid var(--border);
    border-radius:10px;padding:18px}
  figure.diagram pre.mermaid{background:transparent;border:0;padding:0;margin:0;
    text-align:center;font-size:14px}
  figure.diagram figcaption{color:var(--muted);font-size:12px;margin-top:10px;text-align:center}
</style>
</head>
<body>
<div class="wrap">

  <p style="margin:0 0 6px">
    <span class="pill tag {{warn|bad|good|}}">{{TAG e.g. INFO | DRAFT | ACTION NEEDED}}</span>
  </p>
  <h1>{{Report title with inline <code> where useful}}</h1>
  <p class="muted">{{One-sentence summary. What this answers, for whom. No hedging.}}</p>

  <div class="meta">
    <div><div class="k">Topic</div><div class="v">{{topic}}</div></div>
    <div><div class="k">Kind</div><div class="v">{{overview | investigation | ...}}</div></div>
    <div><div class="k">Scope</div><div class="v">{{what's covered / boundaries}}</div></div>
    <div><div class="k">Sources</div><div class="v">{{files / commands / links}}</div></div>
    <div><div class="k">Status</div><div class="v">{{confirmed | in progress | draft}}</div></div>
    <div><div class="k">Owner</div><div class="v">{{who / team, if relevant}}</div></div>
  </div>

  <h2>TL;DR</h2>
  <div class="callout">
    <strong>Summary</strong>
    {{Two or three sentences. The whole report compressed. Concrete.}}
  </div>
  <div class="callout good">
    <strong>Key takeaway</strong>
    {{The one thing the reader should leave with. Drop if redundant.}}
  </div>
  <div class="callout warn">
    <strong>Watch out</strong> (drop if nothing to flag)
    {{The caveat, risk, or open question.}}
  </div>

  <h2>1 · {{First body section per the kind}}</h2>
  <p>{{Prose. Active voice, concrete.}}</p>
  <ul>
    <li><strong>{{Point}}.</strong> {{One sentence.}}</li>
  </ul>

  <figure class="diagram">
<pre class="mermaid">
flowchart LR
  {{client}}["{{Client}}"] -->|{{GET /token}}| {{api}}["{{api/handler.ts}}"]
  {{api}} -->|{{verify}}| {{store}}[("{{token_store}}")]
  {{store}} -->|{{hit}}| {{api}}
  {{api}} -->|{{refreshed JWT}}| {{client}}
</pre>
    <figcaption>{{What the diagram shows, one line.}}</figcaption>
  </figure>

  <h2>2 · {{Next section — often a table}}</h2>
  <table>
    <thead><tr><th>{{Col}}</th><th>{{Col}}</th><th class="num">{{Num}}</th><th>{{Notes}}</th></tr></thead>
    <tbody>
      <tr><td><code>{{thing}}</code></td><td>{{value}}</td><td class="num">{{42}}</td><td>{{...}}</td></tr>
    </tbody>
  </table>

  <h2>3 · {{Evidence / flow / options as the kind requires}}</h2>
  <p>{{Setup or framing in one short paragraph.}}</p>
<pre>{{command output, code, or repro — verbatim}}</pre>
  <div class="callout good"><strong>Result</strong> {{One-sentence verdict.}}</div>

  <details class="code">
    <summary>Supporting detail — click to expand</summary>
    <div class="body">
      <h3>{{label}}</h3>
<pre>{{full dump: logs, config, long code}}</pre>
    </div>
  </details>

  <div class="callout">
    <strong>Bottom line</strong>
    {{One paragraph. The conclusion, recommendation, or next step.}}
  </div>

  <footer>
    {{Report kind}} on {{topic}} ·
    sources: {{files / commands / links}} ·
    {{how verified, if applicable}}
  </footer>

</div>

<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
  mermaid.initialize({
    startOnLoad: true,
    theme: "dark",
    themeVariables: {
      background: "#161b22", primaryColor: "#1c2230", primaryTextColor: "#e6edf3",
      primaryBorderColor: "#30363d", lineColor: "#58a6ff", fontSize: "14px",
    },
  });
</script>
</body>
</html>
```

If the report has no diagram, drop the `<figure class="diagram">` block. Keep the
Mermaid `<script>` only when at least one diagram is present.

## Component cheatsheet

| Need | Markup |
|------|--------|
| Status pill (default = info/blue) | `<span class="pill tag">INFO</span>` |
| Warn pill | `<span class="pill tag warn">DRAFT</span>` |
| Bad pill | `<span class="pill tag bad">ACTION NEEDED</span>` |
| Good pill | `<span class="pill tag good">FINAL</span>` |
| Good callout | `<div class="callout good">…</div>` |
| Bad callout | `<div class="callout bad">…</div>` |
| Warn callout | `<div class="callout warn">…</div>` |
| Diff line added | `<span class="add">+ ...</span>` |
| Diff line removed | `<span class="del">- ...</span>` |
| Diff hunk header | `<span class="hdr">@@ ... @@</span>` |
| Inline muted note | `<span class="muted">// note</span>` |
| Numeric table column | `<td class="num">42</td>` |
| Stepped flow | `<div class="flow"><span class="n">1.</span> …</div>` |
| Mermaid diagram | `<figure class="diagram"><pre class="mermaid">flowchart LR …</pre><figcaption>…</figcaption></figure>` |
| Collapsible detail dump | `<details class="code"><summary>…</summary><div class="body">…</div></details>` |
| Keyboard hint | `<kbd>bun test</kbd>` |

## Quality gate before writing

Before the Write call, re-read the draft and confirm:

- [ ] Tag pill at top, H1 second, meta grid third, TL;DR fourth
- [ ] TL;DR summarizes the whole report in plain language
- [ ] Body sections match the chosen kind; no empty placeholder headings
- [ ] Every claim is concrete (path, number, date, quote) — no vague filler
- [ ] At least one table, flow, or code block where the topic supports it
- [ ] A diagram present if the topic has a flow, structure, or interaction;
      Mermaid `<script>` included iff a diagram is present
- [ ] Diagram nodes use real names, each diagram shows one idea
- [ ] Bottom-line callout states the conclusion / recommendation / next step
- [ ] Footer names the sources
- [ ] No em-dashes in prose
- [ ] Headings numbered with `·`
- [ ] Links to code / docs / tickets included where they help the reader
