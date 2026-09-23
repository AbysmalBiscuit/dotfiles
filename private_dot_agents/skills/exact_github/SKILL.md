---
name: github
description: >-
  Use when a GitHub action has no obvious `gh` command or behaves unexpectedly:
  linking a stacked or cross-repo PR to an issue.
---

# GitHub recipes

Recipes for GitHub actions that `gh --help` and the docs don't make obvious. Read the matching reference before improvising with `gh api`.

- Linking a PR to an issue when `Closes #N` didn't link it (stacked PR, PR not targeting the default branch, issue in another repo): [`references/link-pr-to-issue.md`](references/link-pr-to-issue.md)
