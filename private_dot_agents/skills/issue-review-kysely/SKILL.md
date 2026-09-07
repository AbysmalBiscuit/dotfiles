---
name: issue-review-kysely-irk
description: Push the current issue worktree and open/update its PR with no reviewer and no Slack DM
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
---
# /issue-review-kysely

Ship a finished (or just-updated) issue worktree: commit, push, open **or** reuse the
PR. **No reviewer is added and no Slack message is sent** — I am doing the rest of the
cleanup myself and nobody needs pinging.

This deliberately does **not** call `issue review request`. That subcommand adds the reviewer on GitHub and delivers the `review_request` Slack template. `issue pr create` opens the PR through the same `pr_title` / `pr_body` templates while adding no reviewer and sending no Slack, so Branch A uses that instead.

## What already happened

`~/.agents/skills/issue-review-kysely/scripts/issue_review_recon.py` has **already run**, read-only. It detected the PR state, picked the branch of the workflow that applies, and gathered the diff you need. Its output is below.

It ends with `IR-BRANCH: A | B | STOP` and `IR-RESULT: <STATUS>`. Everything you need about worktree, PR, and diff state is in that output. Do not re-run `issue info`, `gh pr view`, `git status`, `git log`, or `git diff` to orient yourself.

This skill has its own recon script, separate from `/issue-review`'s. It takes no reviewer alias, resolves none, and never prints an `issue review request` line, so every line of its output applies here.

It deliberately did **not** commit or push — those need prose only you can write. That is the work left for you.

---

!`python3 ~/.agents/skills/issue-review-kysely/scripts/issue_review_recon.py 2>&1 || true`

---

## Act on the result

| `IR-RESULT` | What to do |
|---|---|
| `READY` + `IR-BRANCH: A` | No PR yet — Branch A below. |
| `READY` + `IR-BRANCH: B` | PR already open — Branch B below. |
| `NOTHING-NEW` | HEAD is already pushed and the tree is clean. Report the PR URL. Stop. |
| `PR-MERGED` / `PR-CLOSED` | Report it; there is nothing to push. Stop. |
| `PROTECTED` | Report the branch and ask which worktree they meant. Stop. |
| `NOT-ISSUE-WORKTREE` | Report it and ask — without an issue record you cannot stamp the Linear id onto the PR. Stop. |
| `ERROR` | Read the message, fix the precondition, re-run the script. |

On `READY`, open the steps of the branch named in `IR-BRANCH` as tasks — `TaskCreate` one
per step, `TaskUpdate` each to `in_progress` as you start it and `completed` as it lands —
then work them. If those tools are unavailable, keep the steps as a list in your replies;
do not go looking for a tracking tool.

Stop and ask if any step below fails or is ambiguous — never force-push, never invent a
summary the diff doesn't support.

### Branch A — no PR yet

1. **Judge the work.** The diff is above. Confirm the change is actually complete and
   coherent before shipping it. Untracked files are listed separately — decide whether
   each belongs in the commit.
2. **Commit** anything pending with a conventional-commit message derived from the issue
   + diff.
3. **Draft the PR title + body** with the **`/write` skill**. Write them *without* the
   Linear id; the templates stamp it in step 4, and each stamp drops out if the drafted
   text already carries it.
4. **Push and open the PR — no reviewer, no Slack:**

   ```bash
   issue pr create --ready \
     --pr-title "<conventional-commit subject>" \
     --pr-body  "<what changed + why>"
   ```

   It pushes, renders `pr_title` (the ` [<ISSUE>]` suffix) and `pr_body` (the `## Linear`
   section carrying `Closes <ISSUE>`), opens the PR ready for review, and prints the URL.
   No `base` to look up: it uses the configured `defaults.pr_base`. Pass no `--to` and
   nobody is added on GitHub and nothing goes to Slack.

   Add `--arg linear_magic_word=Ref` if merging this PR must **not** close the issue
   (partial work, one of several PRs) — it still links, but merging won't transition the
   issue. Other contributing words: `references`, `part of`, `related to`,
   `contributes to`, `towards`. Ask the user if it's unclear whether the PR closes it.
5. **Report** the PR URL. Do not Slack anyone.

### Branch B — PR already open

1. **Judge the work.** The diff above is scoped to what is not yet on the pushed tip (or
   not yet reviewed). Confirm it is coherent.
2. **Commit** anything pending with a conventional-commit message describing the changes.
3. **Push:**

   ```bash
   git push origin "$(git rev-parse --abbrev-ref HEAD)"
   ```

4. **Report** the PR URL and a 1–2 sentence summary of what landed, backed by the diff.
   Leave the PR's existing reviewers exactly as they are — do not add, remove, or
   re-request anyone, and do not Slack.

## Notes

- Never run `issue review request` from this command — it always notifies.
- Never send a Slack message from this command, in any form, including as a "heads up".
- Never force-push. A plain `git push` that fails on divergence is the signal to surface
  the error and ask — do not retry blindly.
- If the branch has no upstream yet, `git push -u origin <branch>` is the first push;
  afterwards a plain `git push` is enough.
- If `issue pr create` fails, show the exact error and stop.
