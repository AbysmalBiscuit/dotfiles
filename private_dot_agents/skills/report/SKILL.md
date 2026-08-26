---
name: report-r
description: "Use when you need to generate a standardized self-contained HTML report for summarizing and giving context about anything"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash(~/.agents/skills/report/scripts/report.py:*), Read, Write, Edit, Bash, Grep, Glob, TaskCreate, TaskUpdate, TaskList, TaskGet
---
# /report

Build a self-contained HTML report. `report.py` assembles the page
from a shared theme and lints it, so every report reads as one series and you
only write content.

## Steps

1. **Gather.** Read the named files, run the named commands, fetch the links.
   Collect paths, numbers, dates, quotes. Read the whole function around every
   citation, its callers, the types it touches.
2. **Verify** every claim you can check, and cite the result verbatim
   (`exit code 137 (OOM)`). Track verified against merely quoted; Method &
   limitations needs that split.
3. **Scaffold.** `report.py new --help` lists the kinds and flags. Infer title,
   kind, and tag from the request; ask only for what you cannot infer.
   ```bash
   ~/.agents/skills/report/scripts/report.py new --title "Auth token refresh flow" \
     --kind overview --tag DRAFT --tag-style warn
   ```
4. **Write the body** for a **cold reader** who has never opened this repo:
   [`references/writing.md`](references/writing.md). Markup for tables, callouts,
   permalinks, TOC, and the fixed sections:
   [`references/components.md`](references/components.md). Replace every
   placeholder; delete any section with no content and its TOC entry with it.
5. **Diagram** anything with a flow, structure, or multi-actor interaction:
   [`references/diagrams.md`](references/diagrams.md).
6. **Check** until it exits 0. It catches leftover placeholders, TOC drift,
   missing expand buttons, unfilled `REPO`/`SHA`, em-dashes in prose, unlabelled
   edges, and every mermaid block through `mmdc`.
   ```bash
   ~/.agents/skills/report/scripts/report.py check path/to/<slug>.html
   ```
7. **Look at the diagrams.** `report.py render reports/<slug>.html` writes a PNG
   each. Read them. A diagram parses clean and is still an unreadable tangle.
8. **Gate.** Walk the checklist closing
   [`references/writing.md`](references/writing.md). Every item holds, or return
   to step 4.
9. Print the path and a one-line summary.
