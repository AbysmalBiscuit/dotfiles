#!/usr/bin/env python3
"""Markdown prose reflowed by hand at a fixed column.

Editors, diff views and every renderer wrap on their own, so a hand-wrapped
paragraph buys nothing and costs every later edit: changing one word reflows
lines that did not change, and the diff shows a paragraph rewritten instead of
a word. Tree-sitter discards the line breaks this depends on, so the check
cannot be an ast-grep rule.

A paragraph is called hand-wrapped when three or more consecutive prose lines
sit in a narrow band of widths and every break is forced: the first word of the
next line could not have fitted on the line before it. A break that was not
forced is a deliberate one (one clause per line, a sentence per line) and takes
the whole paragraph out of scope.
"""

import re
import sys

RULE = "md-hard-wrap"
MESSAGE = (
    "paragraph is hand-wrapped at about column {width}; write each paragraph as "
    "one line and let the renderer wrap it"
)

MIN_LINES = 3
# Below this a short paragraph looks wrapped by coincidence; above it the lines
# are long enough that nothing was wrapping them to a column in the first place.
MIN_COLUMN = 45
MAX_COLUMN = 110
# How far under the widest line the other lines may sit. A real reflow leaves a
# tight right edge; prose broken for meaning does not.
BAND = 25
MAX_REPORTED = 3
SUFFIXES = (".md", ".mdx", ".markdown")
# A reflow breaks wherever the column runs out, which lands mid-sentence far
# more often than not. A run whose lines mostly stop at a sentence boundary is
# one statement per line, written that way on purpose.
SENTENCE_END = re.compile(r"[.!?:;]$")

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
LIST_ITEM = re.compile(r"^\s{0,3}([-*+]|\d+[.)])\s")
# Lines that are not flowing prose: headings, tables, quotes, thematic breaks,
# raw HTML, link reference definitions and indented code.
NOT_PROSE = re.compile(
    r"^(\s{4,}|\s{0,3}(#{1,6}\s|\||>|<|\[[^\]]+\]:\s|([-*_])\s*(\3\s*){2,}$))"
)


def paragraphs(lines):
    """Runs of consecutive prose lines, as (first line number, texts). A list
    item opens a run of its own: its marker line and any continuation under it
    are one wrapped unit, and the item above it is another."""
    current, start = [], 0
    fence = ""
    for number, raw in enumerate(lines, 1):
        text = raw.rstrip("\n").rstrip()
        opener = FENCE.match(text)
        if fence:
            if opener and opener.group(1)[0] == fence[0] and len(opener.group(1)) >= len(fence):
                fence = ""
            continue
        if opener:
            if current:
                yield start, current
            current, fence = [], opener.group(1)
            continue
        if not text or NOT_PROSE.match(text):
            if current:
                yield start, current
            current = []
            continue
        # A trailing double space is a hard line break the author asked for, so
        # the run it sits in was never a reflow.
        if raw.rstrip("\n").endswith("  "):
            current = []
            continue
        if LIST_ITEM.match(text):
            if current:
                yield start, current
            current, start = [text], number
            continue
        if not current:
            start = number
        current.append(text)
    if current:
        yield start, current


def wrap_column(texts):
    """The column a run was reflowed at, or None when it was not reflowed."""
    if len(texts) < MIN_LINES:
        return None
    widths = [len(t) for t in texts]
    width = max(widths)
    if not MIN_COLUMN <= width <= MAX_COLUMN:
        return None
    if min(widths[:-1]) < width - BAND:
        return None
    closed = sum(1 for t in texts[:-1] if SENTENCE_END.search(t))
    if closed * 2 > len(texts) - 1:
        return None
    for line, following in zip(texts, texts[1:]):
        head = following.split(maxsplit=1)[0] if following.split() else ""
        if len(line) + 1 + len(head) <= width:
            return None
    return width


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    # The extensions setting is one regex for the whole checks/ layer, so each
    # check narrows to the files it has anything to say about.
    if not path.lower().endswith(SUFFIXES):
        return
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return
    # YAML front matter is blanked rather than dropped, so reported line numbers
    # still match the file the agent is looking at.
    if lines[:1] == ["---"] and "---" in lines[1:]:
        end = lines.index("---", 1)
        lines = [""] * (end + 1) + lines[end + 1:]
    findings = []
    for start, texts in paragraphs(lines):
        width = wrap_column(texts)
        if width is not None:
            findings.append(
                "  {}:{}  [{}] {}".format(path, start, RULE, MESSAGE.format(width=width))
            )
    for finding in findings[:MAX_REPORTED]:
        print(finding)


if __name__ == "__main__":
    main()
