---
description: Generate a standardized HTML PR-review report under pr-reviews/
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# /pr-review-report

Generate a single-finding or multi-finding PR-review report as a self-contained
HTML file in `pr-reviews/`. Every report uses the same theme, components, and
section order so they read as one series.

## Inputs

Ask the user for any missing item:

1. **PR number** (e.g. `2497`)
2. **Finding title** (short noun phrase, e.g. `Unconditional adminDb in getMaterial`)
3. **Severity tag** — one of `CRITICAL`, `HIGH`, `LATENT / DEFENSE-IN-DEPTH`,
   `INFO`
4. **Merge status tag** — one of `MERGE BLOCKER`, `NOT A MERGE BLOCKER`
5. **Endpoint(s)** affected (if applicable)
6. **Auth gate** (`useAuthUser` / `useOptionalAuthUser` / `requireStaff` / `none`)
7. **Service / file** containing the issue
8. **Report kind** — `single-issue` (deep dive on one finding) or `multi-issue`
   (regression class with several sub-findings)

## Output

- Path: `pr-reviews/<kebab-slug>.html`
- Slug rules: lowercase, dashes, no dates, no PR number prefix. E.g.
  `issue-1-adminDb-rls-bypass.html`, `context-builder-migration-regressions.html`.
- One self-contained HTML file. CSS inlined. No external assets.

## Workflow

1. Gather context: `gh pr view <num> --json ...`, `gh pr diff <num>`, read the
   files named by the user.
2. Verify empirically when possible. Run probes (`curl`, `psql`, smoketest).
   Capture HTTP codes, error strings, row counts. Cite them verbatim in the
   report.
3. Draft each section per the template below. Skip a section only if it has no
   content — never leave a placeholder heading.
4. Write to `pr-reviews/<slug>.html`.
5. Print the path and a one-line summary to the user.

## Required sections (in order)

A `single-issue` report uses **all** sections. A `multi-issue` report may collapse
sections 7–9 into a single per-finding block but keeps the same component set.

A sticky **left TOC** (`<nav class="toc">`) sits beside the content and lists every
kept `<h2>`. Keep it in sync: one `<li><a href="#id">…</a></li>` per section, each
`<h2>` carries a matching `id` (`tldr`, `how`, `s1`…`s6`, `method`), and you drop a
TOC entry whenever you drop its section (e.g. §4 for non-latent findings). Below
860px it collapses to a `☰ Contents` drawer.

| # | Section | Purpose |
|---|---------|---------|
| 0 | Pills row + H1 + muted subtitle | At-a-glance verdict |
| 1 | `.meta` grid | PR / branch / endpoint / gate / service / status |
| 2 | TL;DR — three `.callout` blocks | What changed · why safe today · why fix |
| 3 | "How to use this report" — read order + pill legend | Orient the reviewer |
| 4 | "1 · The exact change" — diff in `<pre class="diff">` | Show the offending edit |
| 5 | "2 · Why this is a problem" — bulleted reasoning | Mechanism |
| 6 | "3 · Empirical verification" — tables + HTTP/SQL repro | Evidence |
| 7 | "4 · When this turns into a real leak" (latent only) | Trigger conditions |
| 8 | "5 · Codebase sweep" — table of related sites | Scope |
| 9 | "6 · Recommended fix" — Options A / B with diffs | Resolution |
| 10 | `<details class="code">` — full proposed code changes | Auditability |
| 11 | Bottom-line `.callout` | One-paragraph verdict |
| 12 | "Method & limitations" — `.callout warn` | Verified vs quoted; what's left to check |
| 13 | `<footer>` with provenance | Branch, files, evidence source |

## Voice + prose rules

- **Active voice.** "The handler stops attaching `adminDb`." Not "`adminDb` was
  no longer attached."
- **Concrete and definite.** Real paths, real HTTP codes, real error strings.
  Quote errors verbatim: `permission denied for table user (42501)`.
- **Positive form.** "Customers see 0 rows" not "Customers do not see any rows."
- **Omit needless words.** Cut `actually`, `simply`, `basically`, `just`,
  `clearly`, `it should be noted that`.
- **No em-dashes (—) in prose.** Use period, comma, parens, or restructure.
  Em-dashes inside code samples are fine.
- **Section headings use a middle dot for numbering.** `## 1 · The exact change`.
- **Heading nouns specific.** "Codebase sweep" beats "Other findings."
- **One tense per section.** Past for verification, present for current state.

## HTML skeleton

Copy this verbatim. Replace placeholders inside `{{double-braces}}` only.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>{{Finding title — short}}</title>
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
  .pill.sev{background:#3b2300;color:var(--warn);border:1px solid #5a3a00}
  .pill.sev.critical{background:#3a0d0d;color:var(--bad);border-color:#5a1717}
  .pill.sev.info{background:#0d2336;color:var(--accent);border-color:#1a3a5a}
  .pill.block{background:#0f2e16;color:var(--good);border:1px solid #1b5e2a}
  .pill.block.blocker{background:#3a0d0d;color:var(--bad);border-color:#5a1717}
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
      <li><a href="#s1">1 · The exact change</a></li>
      <li><a href="#s2">2 · Why this is a problem</a></li>
      <li><a href="#s3">3 · Empirical verification</a></li>
      <li><a href="#s4">4 · When this turns into a real leak</a></li>
      <li><a href="#s5">5 · Codebase sweep</a></li>
      <li><a href="#s6">6 · Recommended fix</a></li>
      <li><a href="#method">Method &amp; limitations</a></li>
    </ol>
  </nav>

  <main class="content">

  <p style="margin:0 0 6px">
    <span class="pill sev {{critical|info|}}">SEVERITY: {{HIGH | LATENT / DEFENSE-IN-DEPTH | ...}}</span>
    &nbsp; <span class="pill block {{blocker|}}">{{NOT A MERGE BLOCKER | MERGE BLOCKER}}</span>
  </p>
  <h1>{{Finding title with inline <code> where useful}}</h1>
  <p class="muted">{{One-sentence summary. Concrete. No hedging.}}</p>

  <div class="meta">
    <div><div class="k">PR</div><div class="v">#{{N}} — {{title}}</div></div>
    <div><div class="k">Branch</div><div class="v">{{head}} → {{base}}</div></div>
    <div><div class="k">Endpoint</div><div class="v">{{METHOD /path}}</div></div>
    <div><div class="k">Auth gate</div><div class="v">{{useAuthUser | ...}}</div></div>
    <div><div class="k">Service</div><div class="v">{{path/to/file.ts → fn}}</div></div>
    <div><div class="k">Status</div><div class="v">{{Real in code · empirically reproduced | latent | ...}}</div></div>
  </div>

  <h2 id="tldr">TL;DR</h2>
  <div class="callout">
    <strong>What changed</strong>
    {{One paragraph. The diff in plain English. Name the function, the client,
    the table.}}
  </div>
  <div class="callout good">
    <strong>Why it's safe today</strong> (skip block if not latent)
    {{Empirical reason the issue doesn't trigger now. Cite row counts, HTTP
    codes, seed facts.}}
  </div>
  <div class="callout warn">
    <strong>Why it still deserves a fix</strong>
    {{Future change that turns latent into live. Be specific about which change.}}
  </div>

  <h2 id="how">How to use this report</h2>
  <p>Read the TL;DR for the verdict, then §1–§2 for the change and why it matters,
  then §3 for the proof. {{Adjust to the finding: name the section a reviewer
  short on time should jump to.}}</p>
  <table>
    <thead><tr><th>Pill</th><th>Meaning</th><th>Read priority</th></tr></thead>
    <tbody>
      <tr><td><span class="pill sev critical">CRITICAL</span> / <span class="pill sev">HIGH</span></td><td>Exploitable or breaking on a reachable path.</td><td>First</td></tr>
      <tr><td><span class="pill block blocker">MERGE BLOCKER</span></td><td>Must be resolved before this PR merges.</td><td>First</td></tr>
      <tr><td><span class="pill sev info">LATENT / INFO</span></td><td>Safe today; a named future change makes it live.</td><td>Context</td></tr>
      <tr><td><span class="pill block">NOT A MERGE BLOCKER</span></td><td>Worth fixing, does not gate the merge.</td><td>Context</td></tr>
    </tbody>
  </table>
  <p>The <code>⎘ path:Lx-Ly</code> links open the file at the PR's HEAD commit on
  GitHub, anchored to the cited lines. They are permalinks pinned to the SHA, so
  they keep pointing at the right code after the branch moves. What was
  reproduced first-hand versus quoted from the PR is spelled out in
  <a href="#method">Method &amp; limitations</a>.</p>

  <h2 id="s1">1 · The exact change</h2>
  <p><strong>Handler</strong> — <code>{{path}}</code>:</p>
<pre class="diff"><span class="hdr">@@ defineEventHandler @@</span>
<span class="del">-  {{old line}}</span>
<span class="add">+  {{new line}}</span>
</pre>

  <h2 id="s2">2 · Why this is a problem</h2>
  <ul>
    <li><strong>{{Mechanism}}.</strong> {{One sentence.}}</li>
    <li><strong>{{Reach}}.</strong> {{Who can hit it.}}</li>
    <li><strong>{{Blast field}}.</strong> {{What leaks / breaks.}}</li>
  </ul>

  <h2 id="s3">3 · Empirical verification</h2>
  <p>{{Setup: dual servers, local DB seed, JWT minting. One short paragraph.}}</p>
  <table>
    <thead><tr><th>Server</th><th>Request</th><th class="num">HTTP</th><th>Body fragment</th></tr></thead>
    <tbody>
      <tr><td>{{:9100 (staging)}}</td><td><code>{{GET /...}}</code></td><td class="num">{{200}}</td><td>{{...}}</td></tr>
      <tr><td>{{:9200 (branch)}}</td><td><code>{{GET /...}}</code></td><td class="num">{{500}}</td><td><code>{{error string verbatim}}</code></td></tr>
    </tbody>
  </table>
  <div class="callout good"><strong>Result</strong> {{One sentence verdict.}}</div>

  <h2 id="s4">4 · When this turns into a real leak</h2>
  <ul>
    <li><strong>{{Trigger}}.</strong> {{Concrete future change.}}</li>
  </ul>

  <h2 id="s5">5 · Codebase sweep</h2>
  <p>{{Scope of search and what was checked.}}</p>
  <table>
    <thead><tr><th>Site</th><th>Pattern</th><th>Gate</th><th>Verdict</th></tr></thead>
    <tbody>
      <tr><td><code>{{path:line}}</code></td><td><code>{{snippet}}</code></td><td>{{gate}}</td><td class="add">safe</td></tr>
    </tbody>
  </table>

  <h2 id="s6">6 · Recommended fix</h2>

  <h3>Option A (preferred) — {{summary}}</h3>
<pre><span class="add">+ {{added line}}</span>
{{context}}</pre>
  <p class="muted">{{Trade-off / rationale.}}</p>

  <h3>Option B (smallest diff) — {{summary}}</h3>
<pre><span class="add">+ {{added line}}</span></pre>
  <p class="muted">{{Trade-off / rationale.}}</p>

  <details class="code">
    <summary>Full code changes (Option A) — click to expand</summary>
    <div class="body">
      <h3>① <code>{{file}}</code> — {{purpose}}</h3>
<pre>{{full diff with .add/.del spans}}</pre>
    </div>
  </details>

  <div class="callout">
    <strong>Bottom line</strong>
    {{One paragraph verdict. Mergeable? What the fix buys you.}}
  </div>

  <h2 id="method">Method &amp; limitations</h2>
  <p>{{How this review was done: the diff range read, files inspected at HEAD,
  probes run (servers, DB seed, JWTs).}}</p>
  <div class="callout warn">
    <strong>What this does not establish</strong> (drop if everything was reproduced)
    {{Name what was quoted from the PR description or assumed rather than run
    here. Line ranges are "look here", not byte-exact, unless verified.}}
  </div>

  <footer>
    Generated for review of PR&nbsp;#{{N}} · branch <code>{{branch}}</code> ·
    file <code>{{primary file:line range}}</code> ·
    evidence: {{how reproduced — local Supabase, smoketest path, etc.}}
  </footer>

  </main>
</div>

<script>
(function(){
  // Source permalinks: materialise ⎘ links from data-f / data-l, pinned to the PR HEAD.
  // REPO = https://github.com/<owner>/<repo>; SHA = PR HEAD commit (a permalink, not a branch).
  var REPO = "{{https://github.com/owner/repo}}", SHA = "{{pr-head-sha}}";
  document.querySelectorAll("a.src").forEach(function(a){
    var f = a.getAttribute("data-f"); if(!f) return;
    var l = a.getAttribute("data-l") || "", hash = "";
    if(l){ var p = l.split("-"); hash = p.length>1 ? ("#L"+p[0]+"-L"+p[1]) : ("#L"+p[0]); }
    var enc = f.split("/").map(encodeURIComponent).join("/");   // encodes [id] route brackets
    var sha = a.getAttribute("data-sha") || SHA;                // data-sha overrides (e.g. base commit)
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
})();
</script>
</body>
</html>
```

## How to use this report

The "How to use this report" section (id `how`, right after TL;DR) orients a
reviewer who lands cold: the read order for this finding, a small pill-legend
table (severity / blocker / latent), and a one-line note that `⎘` links are
permalinks pinned to the PR HEAD. Keep it short — it is a map, not a summary.

## Source permalinks (`⎘` links)

Cite code by line, not by pasting paths. Write the anchor with data attributes;
the inlined script builds the GitHub URL:

```html
<a class="src" data-f="apps/api/server/utils/db/admin.ts" data-l="1-45"></a>
```

- `data-f` — repo-relative path. `data-l` — line or `start-end` range (omit for a
  whole-file link). Empty anchor text auto-fills to `filename:lines`.
- Set `REPO` and `SHA` once in the script. Pin `SHA` to the PR HEAD commit (not a
  branch) so the links survive a force-push or rebase.
- `data-sha` on an anchor overrides the default — use it to point a "staging
  equivalent" link at the base commit for before/after comparison.
- Prefer these over plain `path:line` text everywhere a reviewer would want to
  click through (meta grid, sweep table, every finding).

## Method & limitations

Close with a "Method & limitations" section (id `method`): the diff range read,
files inspected, probes run, then a `callout warn` naming what was **quoted from
the PR or assumed** versus reproduced here. A review that is honest about its
evidence is trusted; treat the checklist of unverified items as the reviewer's
remaining work, not work already done.

## Component cheatsheet

| Need | Markup |
|------|--------|
| Source permalink | `<a class="src" data-f="path/to/file.ts" data-l="12-40"></a>` (set `REPO`/`SHA` in script) |
| TOC entry | `<li><a href="#s1">1 · The exact change</a></li>` (heading needs matching `id`) |
| Diff line added | `<span class="add">+ ...</span>` |
| Diff line removed | `<span class="del">- ...</span>` |
| Diff hunk header | `<span class="hdr">@@ ... @@</span>` |
| Inline muted note | `<span class="muted">// note</span>` |
| Severity pill (default = warn) | `<span class="pill sev">SEVERITY: HIGH</span>` |
| Critical severity | `<span class="pill sev critical">SEVERITY: CRITICAL</span>` |
| Merge-blocker pill | `<span class="pill block blocker">MERGE BLOCKER</span>` |
| Non-blocker pill | `<span class="pill block">NOT A MERGE BLOCKER</span>` |
| Good callout | `<div class="callout good">…</div>` |
| Bad callout | `<div class="callout bad">…</div>` |
| Warn callout | `<div class="callout warn">…</div>` |
| Numeric table column | `<td class="num">42</td>` |
| Stepped attack flow | `<div class="flow"><span class="n">1.</span> …</div>` |
| Collapsible code dump | `<details class="code"><summary>…</summary><div class="body">…</div></details>` |
| Keyboard hint | `<kbd>bun test</kbd>` |

## Quality gate before writing

Before the Write call, re-read the draft and confirm:

- [ ] Pills at top, H1 second, meta grid third
- [ ] Left TOC lists every kept `<h2>` in order; each links a real `id`; no orphan
      links; scrollspy + mobile-toggle `<script>` kept
- [ ] "How to use this report" present: read order + pill legend + permalink note
- [ ] TL;DR has three callouts (drop "safe today" only for non-latent issues)
- [ ] Every claim is concrete (path, line, HTTP code, error string)
- [ ] At least one empirical table or repro block
- [ ] Sweep section lists either confirmed safe sites or "none found, scope: …"
- [ ] Two fix options, with the preferred one labelled
- [ ] "Method & limitations" present; caveat callout names quoted/assumed vs reproduced
- [ ] Footer names the branch and evidence source
- [ ] No em-dashes in prose
- [ ] Headings numbered with `·`
- [ ] Code cited via `⎘` source permalinks (`data-f`/`data-l`, `REPO`/`SHA` filled
      with the PR HEAD), not bare `path:line` text

## Notes for multi-issue reports

When summarising several findings (regression classes, audit sweeps):

- Lead with a class-comparison table (one row per class) before per-class
  sections.
- Use `<span class="classtag b">Class B</span>` style chips. Add styles to the
  `<style>` block if missing:
  `.classtag{display:inline-block;font-weight:700;font-size:12px;padding:2px 8px;border-radius:5px} .classtag.b{background:#3a0d0d;color:var(--bad)} .classtag.a{background:#3b2300;color:var(--warn)}`
- Each finding gets its own H2 with the class tag in the heading. Give each an
  `id` and a TOC entry so the sidebar maps the whole sweep.
- Skip the per-finding fix-option pair; consolidate fixes in one closing section.
- **End every finding with a skeptical "Check" line** — one sentence stating what
  a reviewer should re-verify rather than take on faith, not a restatement of the
  finding. Mark it `<p class="muted"><strong>Check:</strong> …</p>`. This is the
  single highest-value convention for a multi-finding report: it turns each entry
  from a claim into a prompt for the reviewer's own judgment.
- Anchor every cited site with a `⎘` source permalink so the sweep is clickable.
- Add a "Concerns & open questions" section before the fixes that re-collects the
  `Check` lines flagged security/verify, so the reader sees the must-look items in
  one place.

