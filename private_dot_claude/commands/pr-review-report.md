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

| # | Section | Purpose |
|---|---------|---------|
| 0 | Pills row + H1 + muted subtitle | At-a-glance verdict |
| 1 | `.meta` grid | PR / branch / endpoint / gate / service / status |
| 2 | TL;DR — three `.callout` blocks | What changed · why safe today · why fix |
| 3 | "1 · The exact change" — diff in `<pre class="diff">` | Show the offending edit |
| 4 | "2 · Why this is a problem" — bulleted reasoning | Mechanism |
| 5 | "3 · Empirical verification" — tables + HTTP/SQL repro | Evidence |
| 6 | "4 · When this turns into a real leak" (latent only) | Trigger conditions |
| 7 | "5 · Codebase sweep" — table of related sites | Scope |
| 8 | "6 · Recommended fix" — Options A / B with diffs | Resolution |
| 9 | `<details class="code">` — full proposed code changes | Auditability |
| 10 | Bottom-line `.callout` | One-paragraph verdict |
| 11 | `<footer>` with provenance | Branch, files, evidence source |

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
<div class="wrap">

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

  <h2>TL;DR</h2>
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

  <h2>1 · The exact change</h2>
  <p><strong>Handler</strong> — <code>{{path}}</code>:</p>
<pre class="diff"><span class="hdr">@@ defineEventHandler @@</span>
<span class="del">-  {{old line}}</span>
<span class="add">+  {{new line}}</span>
</pre>

  <h2>2 · Why this is a problem</h2>
  <ul>
    <li><strong>{{Mechanism}}.</strong> {{One sentence.}}</li>
    <li><strong>{{Reach}}.</strong> {{Who can hit it.}}</li>
    <li><strong>{{Blast field}}.</strong> {{What leaks / breaks.}}</li>
  </ul>

  <h2>3 · Empirical verification</h2>
  <p>{{Setup: dual servers, local DB seed, JWT minting. One short paragraph.}}</p>
  <table>
    <thead><tr><th>Server</th><th>Request</th><th class="num">HTTP</th><th>Body fragment</th></tr></thead>
    <tbody>
      <tr><td>{{:9100 (staging)}}</td><td><code>{{GET /...}}</code></td><td class="num">{{200}}</td><td>{{...}}</td></tr>
      <tr><td>{{:9200 (branch)}}</td><td><code>{{GET /...}}</code></td><td class="num">{{500}}</td><td><code>{{error string verbatim}}</code></td></tr>
    </tbody>
  </table>
  <div class="callout good"><strong>Result</strong> {{One sentence verdict.}}</div>

  <h2>4 · When this turns into a real leak</h2>
  <ul>
    <li><strong>{{Trigger}}.</strong> {{Concrete future change.}}</li>
  </ul>

  <h2>5 · Codebase sweep</h2>
  <p>{{Scope of search and what was checked.}}</p>
  <table>
    <thead><tr><th>Site</th><th>Pattern</th><th>Gate</th><th>Verdict</th></tr></thead>
    <tbody>
      <tr><td><code>{{path:line}}</code></td><td><code>{{snippet}}</code></td><td>{{gate}}</td><td class="add">safe</td></tr>
    </tbody>
  </table>

  <h2>6 · Recommended fix</h2>

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

  <footer>
    Generated for review of PR&nbsp;#{{N}} · branch <code>{{branch}}</code> ·
    file <code>{{primary file:line range}}</code> ·
    evidence: {{how reproduced — local Supabase, smoketest path, etc.}}
  </footer>

</div>
</body>
</html>
```

## Component cheatsheet

| Need | Markup |
|------|--------|
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
- [ ] TL;DR has three callouts (drop "safe today" only for non-latent issues)
- [ ] Every claim is concrete (path, line, HTTP code, error string)
- [ ] At least one empirical table or repro block
- [ ] Sweep section lists either confirmed safe sites or "none found, scope: …"
- [ ] Two fix options, with the preferred one labelled
- [ ] Footer names the branch and evidence source
- [ ] No em-dashes in prose
- [ ] Headings numbered with `·`
- [ ] When relevant and possible, include links to code line on GitHub (in the PR branch)

## Notes for multi-issue reports

When summarising several findings (regression classes, audit sweeps):

- Lead with a class-comparison table (one row per class) before per-class
  sections.
- Use `<span class="classtag b">Class B</span>` style chips. Add styles to the
  `<style>` block if missing:
  `.classtag{display:inline-block;font-weight:700;font-size:12px;padding:2px 8px;border-radius:5px} .classtag.b{background:#3a0d0d;color:var(--bad)} .classtag.a{background:#3b2300;color:var(--warn)}`
- Each finding gets its own H2 with the class tag in the heading.
- Skip the per-finding fix-option pair; consolidate fixes in one closing section.

