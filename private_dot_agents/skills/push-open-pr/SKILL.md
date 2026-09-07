---
name: push-open-pr-popr
description: use when wrapping up working on a feature and its time to push and open a PR
disable-model-invocation: true
user-invocable: true
argument-hint: "[optional: extra context for the PR description]"
---
Commit anything pending, draft a title and body with the **`/write` skill**, then:

```bash
issue pr create --ready \
  --pr-title "<conventional-commit subject>" \
  --pr-body  "<what changed + why>"
```

It pushes, opens the PR, and prints the URL. Report the URL.

Write a plain subject and plain body prose. The devkit templates add the ` [SWE-123]`
suffix and the `Closes SWE-123` line, each dropping out if your own text already carries
it, plus a `## TL;DR` placeholder for Lev that is emitted unconditionally — write your own
and you get the heading twice. Add `--arg linear_magic_word=Ref` when merging this PR must
not close the issue.

- `issue pr create` adds no reviewer and sends no Slack. It is the quiet path by default;
  `issue review request` is what notifies, and it needs the PR to exist first.
- `--ready` opens a real PR rather than a draft, whatever `defaults.pr_create_state` says.
  Drafts do not get review-bot coverage.
- `--pr-title` / `--pr-body` render only at creation. On an existing PR they are ignored
  with no error; `gh pr edit` is the way in afterwards.
- The push is a plain `git push -u`. If the branch has diverged it fails — report it and
  stop; `/rebase-latest-force-push` is the fix.

Reviewer needed, or the full template rules? `/issue-review`.
