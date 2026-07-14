---
description: Generate a standardized self-contained HTML report under reports/ for summarizing and giving context about anything
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, TaskCreate, TaskUpdate, TaskList, TaskGet
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
   links. Collect concrete facts — paths, numbers, dates, quotes. Read enough
   surrounding code to explain it, not just the one line you cite — the function
   it lives in, its callers, the types it touches. The reader has not seen the
   code; assume zero prior knowledge of the file.
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
**always present**. "How to use this report" and "Method & limitations" are
present whenever the report is long enough to need a reading path, uses pills, or
cites code (drop them only for a trivial one-screen status). The rest vary:

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

### Make every diagram readable — expand button + orientation

The content column is ~960px. A diagram with more than about four nodes, or with
any real label text on them, gets scaled down to fit and becomes unreadable at
rest. Two things fix that, and both are cheap, so do both every time:

- **Give every diagram the expand button.** Put `<button class="zoom" type="button">⤢ Expand</button>`
  as the first child of the `<figure class="diagram">`. The inlined script clones
  the rendered SVG into a fullscreen overlay (Esc, ✕, or backdrop-click to close),
  so the reader can always blow it up regardless of how small it renders inline.
  This costs one line per figure and removes the whole class of "I can't read the
  diagram" complaints. Keep the `#lightbox` div and its script block whenever any
  diagram is present.
- **Prefer `flowchart TD` over `LR` for chains.** A left-to-right chain of 5+ nodes
  gets squeezed hard in a 960px column, while top-down uses the page's infinite
  vertical space and stays legible. Reach for `LR` only for genuinely short
  or wide-by-nature diagrams. `sequenceDiagram` and `erDiagram` set their own
  orientation, so this applies mainly to flowcharts.

Put load-bearing numbers **on the diagram** (`dna_sequence<br/><small>71,273 rows ·
159 MB</small>`), and style the edge that carries the point so it reads at a
glance (`linkStyle 5 stroke:#d29922,stroke-width:2px`). A diagram that restates
the prose adds nothing; one that carries the argument earns its space.

### Validate the Mermaid before writing

Mermaid fails silently in the browser: a syntax error renders as a blank box or
raw source, and you will not notice from the file alone. Check it with `mmdc`
before you ship the report. Write the diagram source to a scratch `.mmd` and run:

```bash
mmdc -i diagram.mmd -o diagram.png -b '#161b22' -w 900
```

A non-zero exit means it will not render. Render to PNG and **look at it** rather
than trusting the exit code, since a diagram can parse fine and still be an
unreadable tangle. That is also the cheapest way to catch nodes that overlap or
labels that overflow.

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

## Context — show enough

The most common failure is assuming the reader already knows the code. They do
not. A report that names a function without showing it, or cites a bug without
the surrounding lines, forces the reader to go open the file — which defeats the
report. Make every claim legible on its own.

- **Show the code you talk about.** When a sentence turns on a specific function,
  branch, or config value, paste the relevant lines in a `<pre>` (or a
  `<details class="code">` for long dumps) right next to the prose. Quote the
  exact lines, not a paraphrase. A `⎘` permalink is the *pointer*, not a
  substitute for showing the snippet.
- **Frame before you cite.** Before a snippet, say in one line what file it is
  from, what it does, and why it matters here. Reader should never hit code cold.
- **Define the unfamiliar.** Spell out the domain terms, acronyms, env vars,
  table names, and function roles the first time they appear. One clause is
  enough: "`reconcile()` (the nightly job that re-syncs balances)".
- **Give the starting state.** What did the reader need to know going in — what
  the system does, where the code lives, what the normal path looks like — before
  the specific point lands. Orient, then dive.
- **Trace the path, don't just name endpoints.** "Handler calls `verify()` which
  reads `token_store`" beats "the token is verified." Name each hop with its real
  symbol so the reader can follow without the source open.
- **Prefer showing over asserting.** Instead of "the retry logic is wrong," show
  the loop and point at the line. The evidence carries the claim.

Self-test before writing: could a teammate who has never opened this repo follow
the report end to end without leaving the page? If not, add the missing snippet,
definition, or framing sentence.

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
  .layout{display:grid;grid-template-columns:240px minmax(0,960px);gap:40px;
    max-width:1240px;margin:0 auto;padding:40px 24px 96px;justify-content:center}
  .content{min-width:0}
  .toc{position:sticky;top:24px;align-self:start;max-height:calc(100vh - 48px);
    overflow:auto;font-size:13px;border-right:1px solid var(--border);padding-right:8px}
  .toc .t{color:var(--muted);text-transform:uppercase;letter-spacing:.04em;
    font-size:11px;margin:0 0 10px}
  .toc ol{list-style:none;margin:0;padding:0}
  .toc li{margin:2px 0}
  .toc a{display:block;color:var(--muted);text-decoration:none;padding:4px 8px;
    border-radius:6px;border-left:2px solid transparent;line-height:1.35}
  .toc a:hover{color:var(--fg);background:var(--panel)}
  .toc a.active{color:var(--accent);border-left-color:var(--accent);background:var(--panel)}
  a.src{font-family:"SF Mono","JetBrains Mono",Menlo,Consolas,monospace;font-size:.82em;
    color:var(--accent);text-decoration:none;border-bottom:1px dotted var(--accent);white-space:nowrap}
  a.src::before{content:"⎘ ";opacity:.6}
  a.src:hover{background:var(--panel2)}
  #menu-btn{display:none;position:fixed;top:12px;left:12px;z-index:50;
    background:var(--accent);color:var(--bg);border:0;border-radius:6px;
    padding:8px 12px;font-size:14px;font-weight:600;cursor:pointer}
  @media(max-width:860px){
    .layout{grid-template-columns:minmax(0,1fr);max-width:960px}
    .toc{position:fixed;top:0;left:0;width:260px;height:100vh;z-index:40;max-height:none;
      background:var(--panel);border-right:1px solid var(--border);
      transform:translateX(-100%);transition:transform .2s;
      box-shadow:2px 0 12px rgba(0,0,0,.4);padding:20px 16px}
    .toc.open{transform:none}
    #menu-btn{display:block}
  }
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
    border-radius:10px;padding:18px;position:relative}
  figure.diagram pre.mermaid{background:transparent;border:0;padding:0;margin:0;
    text-align:center;font-size:14px}
  figure.diagram pre.mermaid svg{max-width:100%;height:auto}
  figure.diagram figcaption{color:var(--muted);font-size:12px;margin-top:10px;text-align:center}
  button.zoom{position:absolute;top:10px;right:10px;z-index:2;display:flex;align-items:center;
    gap:6px;background:var(--panel2);color:var(--muted);border:1px solid var(--border);
    border-radius:6px;padding:5px 10px;font-size:12px;font-weight:600;cursor:pointer;
    font-family:inherit;transition:color .15s,border-color .15s}
  button.zoom:hover{color:var(--accent);border-color:var(--accent)}
  #lightbox{display:none;position:fixed;inset:0;z-index:100;background:rgba(6,9,13,.94);
    padding:32px 24px 24px;overflow:auto}
  #lightbox.open{display:flex;flex-direction:column}
  #lightbox .lb-bar{display:flex;justify-content:space-between;align-items:center;
    color:var(--muted);font-size:13px;margin-bottom:12px;flex:0 0 auto}
  #lightbox .lb-close{background:var(--panel2);color:var(--fg);border:1px solid var(--border);
    border-radius:6px;padding:6px 12px;font-size:13px;font-weight:600;cursor:pointer;font-family:inherit}
  #lightbox .lb-close:hover{border-color:var(--accent);color:var(--accent)}
  #lightbox .lb-stage{flex:1 1 auto;display:flex;align-items:center;justify-content:center;min-height:0}
  #lightbox .lb-stage svg{max-width:100%!important;max-height:100%;width:auto;height:auto}
</style>
</head>
<body>
<button id="menu-btn" aria-label="Toggle contents">☰ Contents</button>
<div class="layout">

  <nav class="toc">
    <p class="t">On this page</p>
    <ol>
      <li><a href="#tldr">TL;DR</a></li>
      <li><a href="#how">How to use this report</a></li>
      <li><a href="#s1">1 · {{First body section}}</a></li>
      <li><a href="#s2">2 · {{Next section}}</a></li>
      <li><a href="#s3">3 · {{Evidence / flow / options}}</a></li>
      <li><a href="#method">Method &amp; limitations</a></li>
    </ol>
  </nav>

  <main class="content">

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

  <h2 id="tldr">TL;DR</h2>
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

  <h2 id="how">How to use this report</h2>
  <p>{{Reading path: which section to read first and why, then the order to walk
  the rest. Name the one section that frames everything else.}}</p>
  <ul>
    <li><strong>Pills / callouts.</strong> {{What the status pills and coloured
    callouts mean here, and which to read first. Drop if the report uses none.}}</li>
    <li><strong>Source links.</strong> The <code>⎘ path:Lx-Ly</code> links open the
    file at a pinned commit, anchored to the cited lines. {{Drop if no code is cited.}}</li>
    <li><strong>Verified vs quoted.</strong> {{Say what was checked first-hand
    versus taken from a description or third party. See Method &amp; limitations.}}</li>
  </ul>

  <h2 id="s1">1 · {{First body section per the kind}}</h2>
  <p>{{Prose. Active voice, concrete.}}</p>
  <ul>
    <li><strong>{{Point}}.</strong> {{One sentence.}}</li>
  </ul>

  <figure class="diagram">
    <button class="zoom" type="button">⤢ Expand</button>
<pre class="mermaid">
flowchart TD
  {{client}}["{{Client}}"] -->|{{GET /token}}| {{api}}["{{api/handler.ts}}"]
  {{api}} -->|{{verify}}| {{store}}[("{{token_store}}")]
  {{store}} -->|{{hit}}| {{api}}
  {{api}} -->|{{refreshed JWT}}| {{client}}
</pre>
    <figcaption>{{What the diagram shows, one line.}} Click <strong>Expand</strong> to enlarge.</figcaption>
  </figure>

  <h2 id="s2">2 · {{Next section — often a table}}</h2>
  <table>
    <thead><tr><th>{{Col}}</th><th>{{Col}}</th><th class="num">{{Num}}</th><th>{{Notes}}</th></tr></thead>
    <tbody>
      <tr><td><code>{{thing}}</code></td><td>{{value}}</td><td class="num">{{42}}</td><td>{{...}}</td></tr>
    </tbody>
  </table>

  <h2 id="s3">3 · {{Evidence / flow / options as the kind requires}}</h2>
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

  <h2 id="method">Method &amp; limitations</h2>
  <p>{{How this report was assembled: files read, commands run, links fetched.}}</p>
  <div class="callout warn">
    <strong>What this does not establish</strong> (drop if everything was verified)
    {{Name what was quoted from a description or assumed rather than reproduced
    first-hand. Line ranges are "look here", not byte-exact, unless checked.}}
  </div>

  <footer>
    {{Report kind}} on {{topic}} ·
    sources: {{files / commands / links}} ·
    {{how verified, if applicable}}
  </footer>

  </main>
</div>

<!-- Diagram lightbox. Keep iff the report has at least one diagram; drop with them. -->
<div id="lightbox" role="dialog" aria-modal="true" aria-label="Enlarged diagram">
  <div class="lb-bar">
    <span id="lb-caption"></span>
    <button class="lb-close" type="button">✕ Close <span class="muted">(Esc)</span></button>
  </div>
  <div class="lb-stage"></div>
</div>

<script>
(function(){
  // Source permalinks: materialise ⎘ links from data-f / data-l, pinned to a commit.
  // Fill REPO + SHA when the report cites code; delete this block if it cites none.
  var REPO = "{{https://github.com/owner/repo}}", SHA = "{{commit-sha-or-branch}}";
  document.querySelectorAll("a.src").forEach(function(a){
    var f = a.getAttribute("data-f"); if(!f) return;
    var l = a.getAttribute("data-l") || "", hash = "";
    if(l){ var p = l.split("-"); hash = p.length>1 ? ("#L"+p[0]+"-L"+p[1]) : ("#L"+p[0]); }
    var enc = f.split("/").map(encodeURIComponent).join("/");
    var sha = a.getAttribute("data-sha") || SHA;          // data-sha overrides per-link
    a.href = REPO + "/blob/" + sha + "/" + enc + hash;
    a.target = "_blank"; a.rel = "noopener";
    if(!a.textContent.trim()){ var n = f.split("/").pop(); a.textContent = n + (l ? (":"+l) : ""); }
  });
  // Mobile TOC toggle.
  var toc = document.querySelector(".toc"), btn = document.getElementById("menu-btn");
  if(btn && toc){
    btn.addEventListener("click", function(){ toc.classList.toggle("open"); });
    toc.addEventListener("click", function(e){
      if(e.target.tagName==="A" && window.innerWidth<=860) toc.classList.remove("open");
    });
  }
  // Scrollspy: highlight the current section (supports multiple links per id).
  if(toc){
    var links = [].slice.call(toc.querySelectorAll('a[href^="#"]')), map = {};
    links.forEach(function(a){ var id=a.getAttribute("href").slice(1); (map[id]=map[id]||[]).push(a); });
    var targets = Object.keys(map).map(function(id){ return document.getElementById(id); }).filter(Boolean);
    function spy(){
      var y = window.scrollY + 120, cur = null;
      targets.forEach(function(t){ if(t.offsetTop <= y) cur = t.id; });
      links.forEach(function(a){ a.classList.remove("active"); });
      if(cur && map[cur]) map[cur].forEach(function(a){ a.classList.add("active"); });
    }
    window.addEventListener("scroll", spy, {passive:true});
    window.addEventListener("resize", spy); spy();
  }
  // Diagram lightbox: clone the rendered Mermaid SVG into a fullscreen overlay.
  // Mermaid renders async, so read the SVG at click time rather than on load.
  // Drop this block (and #lightbox) if the report has no diagrams.
  var lb = document.getElementById("lightbox");
  if(lb){
    var stage = lb.querySelector(".lb-stage"), cap = lb.querySelector("#lb-caption");
    function close(){ lb.classList.remove("open"); stage.innerHTML = ""; }
    document.querySelectorAll("figure.diagram button.zoom").forEach(function(btn){
      btn.addEventListener("click", function(){
        var fig = btn.closest("figure.diagram");
        var svg = fig.querySelector("pre.mermaid svg");
        if(!svg) return;                                   // not rendered yet
        var clone = svg.cloneNode(true);
        clone.removeAttribute("width"); clone.removeAttribute("height");
        stage.innerHTML = "";
        stage.appendChild(clone);
        var fc = fig.querySelector("figcaption");
        cap.textContent = fc ? fc.textContent.replace(/\s*Click Expand to enlarge\.?\s*$/, "") : "";
        lb.classList.add("open");
      });
    });
    lb.querySelector(".lb-close").addEventListener("click", close);
    lb.addEventListener("click", function(e){ if(e.target === lb) close(); });
    document.addEventListener("keydown", function(e){ if(e.key === "Escape") close(); });
  }
})();
</script>

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

If the report has no diagram, drop the `<figure class="diagram">` block, the
`#lightbox` div, and the lightbox block inside the main `<script>`. Keep the
Mermaid `<script>` only when at least one diagram is present. When any diagram is
present, all three stay, and every figure gets its `⤢ Expand` button.

### Table of contents (left sidebar)

The skeleton renders a sticky left-hand TOC (`<nav class="toc">`) beside the
content. Keep it in sync with the body:

- Add one `<li><a href="#id">…</a></li>` per `<h2>` you keep, in order.
- Every `<h2>` needs a matching `id`. Use `tldr` for TL;DR and `s1`, `s2`, `s3`,
  … for numbered body sections. The link text mirrors the heading (`1 · How it
  works`).
- Drop a TOC entry whenever you drop its section. Never link an `id` that has no
  heading.
- The scrollspy `<script>` highlights the active section as the reader scrolls —
  keep it; it is plain inlined JS, no external asset.
- Below 860px the TOC becomes a slide-in drawer toggled by the `☰ Contents`
  button (`#menu-btn`). Keep both; the script wires them up. No action needed.

### How to use this report

Include a short "How to use this report" section (id `how`, right after TL;DR)
on any report longer than one screen. It tells the reader:

- **Reading path** — which section frames the rest, then the order to walk them.
- **Pill / callout legend** — what the colours mean and which to read first. If
  the report leans on pills, make this a small table (`Pill | Meaning | Read
  priority`). Drop the line if the report uses no pills.
- **Source links** — that `⎘ path:Lx-Ly` links open code at a pinned commit. Drop
  if no code is cited.
- **Verified vs quoted** — point at Method & limitations.

### Source permalinks (`⎘` links)

When the report cites code, link to the exact lines instead of pasting paths as
plain text. Write the anchor with data attributes and let the inlined script
build the URL:

```html
<a class="src" data-f="apps/api/server/utils/db/admin.ts" data-l="1-45"></a>
```

- `data-f` — repo-relative path. `data-l` — line or `start-end` range (omit for a
  whole-file link). Empty anchor text auto-fills to `filename:lines`.
- Set `REPO` and `SHA` once in the script. Pin `SHA` to a commit (not a branch)
  so links stay valid after the branch moves.
- `data-sha` on an individual anchor overrides the default (e.g. to point at a
  "before" commit for comparison).
- If the report cites no code, delete the source-permalink block from the script.

### Method & limitations

Close longer reports with a "Method & limitations" section (id `method`): how the
report was assembled (files read, commands run), then a `callout warn` naming
what was **quoted or assumed** rather than reproduced first-hand. This keeps the
report honest about its evidence and tells the reader what is still theirs to
check. Drop the caveat callout only when every claim was verified.

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
| Mermaid diagram | `<figure class="diagram"><button class="zoom" type="button">⤢ Expand</button><pre class="mermaid">flowchart TD …</pre><figcaption>…</figcaption></figure>` (needs `#lightbox` + its script) |
| Collapsible detail dump | `<details class="code"><summary>…</summary><div class="body">…</div></details>` |
| Keyboard hint | `<kbd>bun test</kbd>` |
| TOC entry | `<li><a href="#s1">1 · How it works</a></li>` (heading needs matching `id`) |
| Source permalink | `<a class="src" data-f="path/to/file.ts" data-l="12-40"></a>` (set `REPO`/`SHA` in script) |

## Quality gate before writing

Before the Write call, re-read the draft and confirm:

- [ ] Tag pill at top, H1 second, meta grid third, TL;DR fourth
- [ ] Left TOC lists every kept `<h2>` in order; each links a real `id`; no
      orphan links; scrollspy + mobile-toggle `<script>` kept
- [ ] "How to use this report" present (unless trivial one-screen report);
      explains reading path, pill legend, and verified-vs-quoted
- [ ] Code cited via `⎘` source permalinks (not bare paths) with `REPO`/`SHA`
      filled; permalink block deleted if no code cited
- [ ] "Method & limitations" present on longer reports; caveat callout names what
      was quoted/assumed vs reproduced
- [ ] TL;DR summarizes the whole report in plain language
- [ ] Body sections match the chosen kind; no empty placeholder headings
- [ ] Every claim is concrete (path, number, date, quote) — no vague filler
- [ ] Every cited function/branch/value is **shown** (snippet near the prose),
      not just named or permalinked
- [ ] Each snippet is framed first (what file, what it does, why it matters);
      no code hits the reader cold
- [ ] Unfamiliar terms, acronyms, env vars, table/function names defined on first
      use; starting state given before the specific point
- [ ] Self-test passed: a teammate who never opened this repo could follow it
      end to end without leaving the page
- [ ] At least one table, flow, or code block where the topic supports it
- [ ] A diagram present if the topic has a flow, structure, or interaction;
      Mermaid `<script>` included iff a diagram is present
- [ ] Diagram nodes use real names, each diagram shows one idea
- [ ] **Every diagram has its `⤢ Expand` button**, and the `#lightbox` div +
      lightbox script are present (all three kept together, or all three dropped)
- [ ] Chains use `flowchart TD` rather than `LR` unless the diagram is genuinely
      short or wide by nature
- [ ] Mermaid validated with `mmdc` (exit 0) **and the rendered PNG eyeballed** —
      it can parse clean and still be an unreadable tangle
- [ ] Bottom-line callout states the conclusion / recommendation / next step
- [ ] Footer names the sources
- [ ] No em-dashes in prose
- [ ] Headings numbered with `·`
- [ ] Links to code / docs / tickets included where they help the reader
