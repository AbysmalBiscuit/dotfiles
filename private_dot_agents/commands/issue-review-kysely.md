---
description: Push the current issue worktree and open/update its PR with no reviewer and no Slack DM [irk]
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# /issue-review-kysely

Ship a finished (or just-updated) issue worktree: commit, push, open **or** reuse the
PR. **No reviewer is added and no Slack message is sent** — I am doing the rest of the
cleanup myself and nobody needs pinging.

This deliberately does **not** call `issue review request`. That subcommand hard-requires
at least one `--to`, always adds the reviewer on GitHub, and always delivers the
`review_request` Slack template. The PR mechanics are done with `gh` here instead, with
the `pr_title` / `pr_body` template behavior reproduced by hand (see Branch A).

## What already happened

`~/.claude/scripts/issue-review-recon.sh` has **already run**, read-only. It detected the
PR state, picked the branch of the workflow that applies, and gathered the diff you need.
Its output is below.

It ends with `IR-BRANCH: A | B | STOP` and `IR-RESULT: <STATUS>`. Everything you need
about worktree, PR, and diff state is in that output. Do not re-run `issue info`,
`gh pr view`, `git status`, `git log`, or `git diff` to orient yourself.

Two parts of that output do **not** apply here and must be ignored:

- the `reviewer:` line — the script resolves an alias unconditionally; nobody is being
  asked to review.
- the whole `== next ==` block — it prints `issue review request` invocations. Use the
  `gh` commands in Branch A / Branch B below instead.

It deliberately did **not** commit or push — those need prose only you can write. That is
the work left for you.

---

!`bash ~/.claude/scripts/issue-review-recon.sh 2>&1 || true`

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
| `UNKNOWN-REVIEWER` | Not a blocker here. Gather the state yourself (`gh pr view`, `git status`, `git diff origin/<base>...HEAD`) and continue with the matching branch. |
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
   Linear id; you append it in step 5 exactly the way the templates would.
4. **Push:**

   ```bash
   git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
   ```

5. **Open the PR — no reviewer.** Use the `base:` and `issue:` values from the recon
   `== context ==` block:

   ```bash
   gh pr create --base <base> \
     --title "<subject> [<ISSUE>]" \
     --body  "<what changed + why>

   Closes <ISSUE>"
   ```

   That reproduces `pr_title` (` [<ISSUE>]` suffix) and `pr_body` (blank line +
   `Closes <ISSUE>`) by hand. Omit each stamp if the drafted text already carries it —
   the templates skip it in that case too. **Do not pass `--reviewer`.**

   Use `Ref <ISSUE>` instead of `Closes <ISSUE>` if merging this PR must **not** close the
   issue (partial work, one of several PRs) — it still links, but merging won't transition
   the issue. Other contributing words: `references`, `part of`, `related to`,
   `contributes to`, `towards`. Ask the user if it's unclear whether the PR closes it.
6. **Report** the PR URL. Do not Slack anyone.

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
- If `gh pr create` fails, show the exact error and stop.
