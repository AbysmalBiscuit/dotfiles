# Components and fixed sections

The scaffold ships the theme and the structural sections. This is the markup for
everything you add inside them.

## Cheatsheet

| Need | Markup |
|------|--------|
| Status pill (default = info/blue) | `<span class="pill tag">INFO</span>` |
| Warn pill | `<span class="pill tag warn">DRAFT</span>` |
| Bad pill | `<span class="pill tag bad">ACTION NEEDED</span>` |
| Good pill | `<span class="pill tag good">FINAL</span>` |
| Callout | `<div class="callout"><strong>Label</strong> …</div>` (add `good` / `bad` / `warn`) |
| Table | `<table><thead><tr><th>Col</th><th class="num">Num</th></tr></thead><tbody>…</tbody></table>` |
| Numeric cell | `<td class="num">42</td>` |
| Verbatim output | `<pre>command output, code, or repro</pre>` |
| Collapsible dump | `<details class="code"><summary>Supporting detail</summary><div class="body"><h3>label</h3><pre>…</pre></div></details>` |
| Diff line added / removed | `<span class="add">+ …</span>` · `<span class="del">- …</span>` |
| Diff hunk header | `<span class="hdr">@@ … @@</span>` |
| Inline muted note | `<span class="muted">// note</span>` |
| Stepped flow | `<div class="flow"><span class="n">1.</span> …</div>` |
| Keyboard hint | `<kbd>bun test</kbd>` |
| Source permalink | `<a class="src" data-f="path/to/file.ts" data-l="12-40"></a>` |
| Diagram | `references/diagrams.md` |
| TOC entry | `<li><a href="#s1">1 &middot; How it works</a></li>` |

## Table of contents

The sticky left sidebar (`<nav class="toc">`) has to stay in sync with the body.
`check` fails on any mismatch.

- One `<li><a href="#id">…</a></li>` per `<h2>` you keep, in body order.
- Every `<h2>` carries an `id`: `tldr`, `how`, `s1`…`sN`, `method`. Link text
  mirrors the heading.
- Drop a section, drop its TOC entry. Never link an id with no heading.
- The scrollspy and the `☰ Contents` drawer below 860px are already wired. Leave
  them alone.

## Source permalinks (`⎘` links)

Cite code by line, not by pasting a path as plain text. Write the anchor with
data attributes and let the inlined script build the URL:

```html
<a class="src" data-f="apps/api/server/utils/db/admin.ts" data-l="1-45"></a>
```

- `data-f` is the repo-relative path. `data-l` is a line or a `start-end` range; omit
  for a whole-file link. Empty anchor text auto-fills to `filename:lines`.
- Set `REPO` and `SHA` once in the script. Pin `SHA` to a commit, never a branch,
  so the links survive the branch moving. `check` warns on a non-sha.
- `data-sha` on one anchor overrides the default, e.g. to point at a "before"
  commit.
- Scaffolding with `--no-code` leaves the permalink block out entirely.

## Fixed sections

**Section 0** (pill, H1, subtitle), **1** (meta grid), **TL;DR**, and the footer
are always present. Body sections come from the kind you scaffolded with. Number
them with a middle dot: `## 1 · How it works`.

**How to use this report** (id `how`) stays on anything longer than one screen:

- Reading path: which section frames the rest, then the order to walk them.
- Pill and callout legend: what the colours mean, which to read first. If the
  report leans on pills, make this a small table: `Pill | Meaning | Read priority`.
- Source links: that `⎘ path:Lx-Ly` opens code at a pinned commit.
- Verified vs quoted: point at Method & limitations.

Drop any bullet the report does not use. Drop the whole section only for a
trivial one-screen status.

**Method & limitations** (id `method`) closes longer reports: how the report was
assembled (files read, commands run, links fetched), then a `callout warn` naming
what was **quoted or assumed** rather than reproduced first-hand. Line ranges are
"look here", not byte-exact, unless you checked. Drop the caveat callout only
when every claim was verified.
