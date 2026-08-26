#!/usr/bin/env python3
"""Scaffold, validate, and preview reports built from template.html.

    report.py new    --title T --kind K [--tag TAG] [--slug S] [flags]
    report.py check  <file.html> [--no-mermaid]
    report.py render <file.html> [--outdir DIR]
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "template.html"

# Body sections per report kind, in order. Section 1 leads the report.
KINDS: dict[str, list[str]] = {
    "overview": ["How it works", "Key components", "Data &amp; flow", "Gotchas", "Pointers"],
    "investigation": ["What happened", "Evidence", "Root cause", "Impact", "Fix &amp; next steps"],
    "decision": ["Context", "Options", "Trade-offs", "Recommendation", "Risks"],
    "comparison": ["Comparison table", "Per-item notes", "Verdict"],
    "status": ["Current state", "Progress", "Risks &amp; blockers", "Next steps"],
}

TAG_CLASS = {"good": "good", "warn": "warn", "bad": "bad", "info": ""}

MERMAID_THEME = {
    "theme": "dark",
    "themeVariables": {
        "background": "#161b22",
        "primaryColor": "#1c2230",
        "primaryTextColor": "#e6edf3",
        "primaryBorderColor": "#30363d",
        "lineColor": "#58a6ff",
        "fontSize": "14px",
    },
}


# ---------------------------------------------------------------- scaffolding

def slugify(title: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return re.sub(r"-{2,}", "-", s)


ASSETS = HERE / "assets"

# Which asset files a report needs, by feature. theme.css and nav.js are unconditional.
DIAGRAM_ASSETS = {"lightbox.html", "lightbox.js", "mermaid-init.html"}
CODE_ASSETS = {"permalinks.js"}

INCLUDE_RE = re.compile(r"^[ \t]*<!--#include\s+([\w.\-]+)\s*-->[ \t]*$")


def resolve_includes(text: str, diagrams: bool, code: bool) -> str:
    """Inline each `<!--#include name-->` from assets/, dropping the ones this
    report does not need. Keeping the pieces verbatim on disk means the theme and
    the lightbox are edited once, not re-typed per report."""
    out: list[str] = []
    for line in text.split("\n"):
        m = INCLUDE_RE.match(line)
        if not m:
            out.append(line)
            continue
        name = m.group(1)
        if (name in DIAGRAM_ASSETS and not diagrams) or (name in CODE_ASSETS and not code):
            continue
        asset = ASSETS / name
        if not asset.is_file():
            raise SystemExit(f"missing asset {asset}")
        out.append(asset.read_text().rstrip("\n"))
    return "\n".join(out)


def build_toc(sections: list[str]) -> str:
    items = ['<li><a href="#tldr">TL;DR</a></li>',
             '<li><a href="#how">How to use this report</a></li>']
    items += [f'<li><a href="#s{i}">{i} &middot; {t}</a></li>'
              for i, t in enumerate(sections, 1)]
    items.append('<li><a href="#method">Method &amp; limitations</a></li>')
    return "\n".join("      " + i for i in items)


DIAGRAM_STUB = """
  <figure class="diagram">
    <button class="zoom" type="button">&#10530; Expand</button>
<pre class="mermaid">
flowchart TD
  {{node}}["{{real symbol or service name}}"] -->|{{what crosses this edge}}| {{next}}["{{...}}"]
</pre>
    <figcaption>{{What the diagram shows, one line.}} Click <strong>Expand</strong> to enlarge.</figcaption>
  </figure>
"""


def build_body(sections: list[str], diagrams: bool) -> str:
    parts = []
    for i, title in enumerate(sections, 1):
        parts.append(f'  <h2 id="s{i}">{i} &middot; {title}</h2>')
        parts.append("  <p>{{Prose. Active voice, concrete. Frame before you cite.}}</p>")
        if i == 1 and diagrams:
            parts.append(DIAGRAM_STUB.strip("\n"))
        parts.append("")
    parts += [
        '  <div class="callout">',
        "    <strong>Bottom line</strong>",
        "    {{One paragraph. The conclusion, recommendation, or next step.}}",
        "  </div>",
        "",
    ]
    return "\n".join(parts)


def cmd_new(args: argparse.Namespace) -> int:
    if args.kind not in KINDS:
        print(f"unknown kind {args.kind!r}; pick one of {', '.join(KINDS)}", file=sys.stderr)
        return 2
    sections = KINDS[args.kind]
    diagrams, code = not args.no_diagrams, not args.no_code

    text = resolve_includes(TEMPLATE.read_text(), diagrams, code)
    title = html.escape(args.title)
    tag = args.tag or ("INFO" if args.kind != "investigation" else "FINDINGS")
    repl = [
        (r"<title>\{\{.*?\}\}</title>", f"<title>{title}</title>"),
        (r'<span class="pill tag \{\{.*?\}\}">\{\{.*?\}\}</span>',
         f'<span class="pill tag {TAG_CLASS.get(args.tag_style, "")}">{html.escape(tag)}</span>'),
        (r"<h1>\{\{.*?\}\}</h1>", f"<h1>{title}</h1>"),
        (r'(<div class="k">Kind</div><div class="v">)\{\{.*?\}\}',
         lambda m: m.group(1) + args.kind),
        (r'(<div class="k">Topic</div><div class="v">)\{\{.*?\}\}',
         lambda m: m.group(1) + title),
        (r"[ \t]*<!--#slot toc-->", build_toc(sections)),
        (r"[ \t]*<!--#slot body-->", build_body(sections, diagrams)),
    ]
    for pat, sub in repl:
        text = re.sub(pat, sub, text, count=1, flags=re.S)

    out = Path(args.out) / f"{args.slug or slugify(args.title)}.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and not args.force:
        print(f"{out} exists; pass --force to overwrite", file=sys.stderr)
        return 2
    out.write_text(text)

    left = len(re.findall(r"\{\{", text))
    print(f"wrote {out}")
    print(f"sections: {', '.join(f'{i} {html.unescape(t)}' for i, t in enumerate(sections, 1))}")
    print(f"{left} {{{{placeholders}}}} to fill. Drop any section with no content, "
          f"and its TOC entry with it.")
    print(f"when done: {Path(__file__).name} check {out}")
    return 0


# ------------------------------------------------------------------- checking

MERMAID_RE = re.compile(r'<pre class="mermaid">(.*?)</pre>', re.S)
MASK_RE = re.compile(r"<(pre|code|script|style)\b.*?</\1>", re.S)
# The three visible link forms from mermaid's flow.jison lexer (solid, thick,
# dotted). `~~~` is a LINK to the parser too, and so consumes a linkStyle index,
# but an invisible link carries no label by design, so it is left out here.
ARROW_RE = re.compile(r"[xo<]?--+[-xo>]|[xo<]?==+[=xo>]|[xo<]?-?\.+-[xo>]?")
LABELLED_RE = re.compile(r"--\s*\S+.*?--+[>xo]")
DIRECTIVE_RE = re.compile(r"^\s*(linkStyle|style|classDef|class|click|%%|subgraph|end\b)")


def mask_code(text: str) -> str:
    """Blank out code and script spans, preserving line numbering, so prose checks
    only see prose."""
    def blank(m: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", m.group(0))
    return MASK_RE.sub(blank, text)


def lines_matching(text: str, pattern: str) -> list[int]:
    return [i for i, l in enumerate(text.split("\n"), 1) if re.search(pattern, l)]


def mermaid_ok(src: str) -> tuple[bool, str]:
    """Parse-check one block. Theme is irrelevant to whether it renders, so this
    skips the config file and feeds the diagram on stdin."""
    if not shutil.which("mmdc"):
        return True, "mmdc not on PATH, skipped"
    with tempfile.TemporaryDirectory() as d:
        p = subprocess.run(["mmdc", "-q", "-i", "-", "-o", str(Path(d) / "d.png")],
                           input=html.unescape(src.strip()) + "\n",
                           capture_output=True, text=True)
        if p.returncode != 0:
            return False, mermaid_error(p.stderr + p.stdout)
    return True, "renders"


def mermaid_error(output: str) -> str:
    """mmdc buries the parse error under a puppeteer stack trace. Keep the lines
    from `Error:` up to the first stack frame."""
    keep: list[str] = []
    for line in output.split("\n"):
        if re.match(r"\s+at |^\s*\w[\w.#]*\s*\(https?://", line):
            if keep:
                break
            continue
        if keep or line.startswith("Error"):
            keep.append(line.rstrip())
    return " / ".join(l for l in keep if l.strip()) or output.strip().split("\n")[0]


def cmd_check(args: argparse.Namespace) -> int:
    path = Path(args.file)
    text = path.read_text()
    prose = mask_code(text)
    errors: list[str] = []
    warns: list[str] = []

    # Placeholders left behind.
    ph = lines_matching(text, r"\{\{")
    if ph:
        errors.append(f"{len(ph)} unfilled {{{{placeholder}}}} on lines {ph[:12]}")

    # TOC and heading ids agree.
    heads = re.findall(r'<h2 id="([^"]+)"', text)
    unided = lines_matching(text, r"<h2(?![^>]*\bid=)")
    if unided:
        errors.append(f"<h2> without id on lines {unided}")
    toc = re.findall(r'<nav class="toc">.*?</nav>', text, re.S)
    if toc:
        links = re.findall(r'href="#([^"]+)"', toc[0])
        for l in links:
            if l not in heads:
                errors.append(f"TOC links #{l} but no <h2 id=\"{l}\"> exists")
        for h in heads:
            if h not in links:
                errors.append(f"<h2 id=\"{h}\"> has no TOC entry")
        if [l for l in links if l in heads] != [h for h in heads if h in links]:
            warns.append("TOC order does not match heading order")

    # Diagram machinery travels as a set.
    figs = len(re.findall(r'<figure class="diagram"', text))
    zooms = len(re.findall(r'<button class="zoom"', text))
    has_lb = 'id="lightbox"' in text
    has_mermaid_js = "mermaid.esm.min.mjs" in text
    if figs != zooms:
        errors.append(f"{figs} diagram figures but {zooms} expand buttons; every figure needs one")
    if figs and not (has_lb and has_mermaid_js):
        errors.append("diagrams present but the #lightbox div or the mermaid <script> is missing")
    if not figs and (has_lb or has_mermaid_js):
        warns.append("no diagrams, but lightbox/mermaid machinery is still in the file")

    # Source permalinks.
    srcs = len(re.findall(r'<a class="src"', text))
    repo = re.search(r'var REPO\s*=\s*"([^"]*)"\s*,\s*SHA\s*=\s*"([^"]*)"', text)
    if srcs and not repo:
        errors.append("⎘ source links present but the permalink script block was deleted")
    if srcs and repo and ("{{" in repo.group(1) + repo.group(2) or not repo.group(1)):
        errors.append("REPO/SHA not filled in the permalink script")
    if repo and re.fullmatch(r"[0-9a-f]{7,40}", repo.group(2)) is None:
        warns.append(f"SHA {repo.group(2)!r} is not a commit sha; branch links rot")
    if not srcs and repo:
        warns.append("no ⎘ source links; the permalink script block can go")

    # Prose rules.
    dashes = lines_matching(prose, r"—")
    if dashes:
        errors.append(f"em-dash in prose on lines {dashes[:12]}")
    badnum = lines_matching(prose, r"<h2[^>]*>\s*\d+\s*[.)-]\s")
    if badnum:
        errors.append(f"numbered heading not using · on lines {badnum}")

    # Mermaid blocks.
    blocks = MERMAID_RE.findall(text)
    for i, src in enumerate(blocks, 1):
        bare = [l for l in src.split("\n")
                if ARROW_RE.search(l) and not DIRECTIVE_RE.match(l)
                and "|" not in l and not LABELLED_RE.search(l)]
        if bare:
            warns.append(f"diagram {i}: {len(bare)} unlabelled edge(s); say what crosses each arrow")
        if re.search(r"subgraph[^\n]*legend", src, re.I):
            errors.append(f'diagram {i}: legend built as a mermaid subgraph; use <div class="dlegend">')
        if re.search(r"flowchart\s+LR", src) and len(ARROW_RE.findall(src)) >= 5:
            warns.append(f"diagram {i}: long LR chain; TD reads better in a 960px column")
        if not args.no_mermaid:
            ok, msg = mermaid_ok(src)
            if not ok:
                errors.append(f"diagram {i}: {msg}")
            elif "skipped" in msg:
                warns.append(f"diagram {i}: {msg}")

    for w in warns:
        print(f"warn  {w}")
    for e in errors:
        print(f"FAIL  {e}")
    if errors:
        print(f"\n{len(errors)} error(s). Fix, then re-run.")
        return 1
    print(f"\nok — {len(heads)} sections, {figs} diagram(s), {srcs} source link(s)"
          + (f", {len(warns)} warning(s)" if warns else ""))
    return 0


# ------------------------------------------------------------------ rendering

def cmd_render(args: argparse.Namespace) -> int:
    if not shutil.which("mmdc"):
        print("mmdc not on PATH; install @mermaid-js/mermaid-cli", file=sys.stderr)
        return 2
    text = Path(args.file).read_text()
    blocks = MERMAID_RE.findall(text)
    if not blocks:
        print("no mermaid blocks in this file")
        return 0
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    cfg = outdir / "mermaid.json"
    cfg.write_text(json.dumps(MERMAID_THEME))
    rc = 0
    for i, src in enumerate(blocks, 1):
        mmd, png = outdir / f"diagram-{i}.mmd", outdir / f"diagram-{i}.png"
        mmd.write_text(html.unescape(src.strip()) + "\n")
        p = subprocess.run(
            ["mmdc", "-q", "-i", str(mmd), "-o", str(png), "-c", str(cfg),
             "-b", "#161b22", "-w", "900", "-s", "2"],
            capture_output=True, text=True)
        if p.returncode != 0:
            rc = 1
            print(f"diagram {i}: FAILED\n{(p.stderr or p.stdout).strip()}")
        else:
            print(f"diagram {i}: {png}")
    if rc == 0:
        print("\nRead each PNG. A diagram can parse clean and still be an unreadable tangle.")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(prog="report.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    n = sub.add_parser("new", help="scaffold a report from the template")
    n.add_argument("--title", required=True, help="short noun phrase, e.g. 'Auth token refresh flow'")
    n.add_argument("--kind", required=True, choices=sorted(KINDS), help=(
        "overview: explain how something works / orient a reader. "
        "investigation: what happened, evidence, root cause. "
        "decision: options weighed, recommendation. "
        "comparison: N things across shared dimensions. "
        "status: current state, progress, risks, next steps."))
    n.add_argument("--tag", help="pill text, e.g. DRAFT / FINAL / ACTION NEEDED")
    n.add_argument("--tag-style", default="info", choices=sorted(TAG_CLASS),
                   help="pill colour (default info)")
    n.add_argument("--slug", help="override the derived filename slug")
    n.add_argument("--out", default="reports", help="output directory (default reports/)")
    n.add_argument("--no-diagrams", action="store_true", help="strip lightbox + mermaid")
    n.add_argument("--no-code", action="store_true", help="strip the ⎘ permalink script")
    n.add_argument("--force", action="store_true")
    n.set_defaults(fn=cmd_new)

    c = sub.add_parser("check", help="lint a finished report")
    c.add_argument("file")
    c.add_argument("--no-mermaid", action="store_true", help="skip mmdc validation")
    c.set_defaults(fn=cmd_check)

    r = sub.add_parser("render", help="render each diagram to PNG so you can look at it")
    r.add_argument("file")
    r.add_argument("--outdir", default="reports/.diagrams")
    r.set_defaults(fn=cmd_render)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
