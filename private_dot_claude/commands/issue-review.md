---
description: Request (re-)review of the current issue worktree via `issue review request` — push, open/reuse the PR, add the reviewer, and Slack them
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__plugin_slack_slack__slack_send_message, mcp__plugin_slack_slack__slack_create_conversation
argument-hint: "[reviewer-alias] (optional — defaults to igor)"
---

# /issue-review

Hand a finished (or just-updated) issue worktree to a reviewer using
`issue review request`, which does the mechanics: pushes the branch, opens **or**
reuses the PR, adds the GitHub reviewer, and Slacks them the body + PR link.

## What already happened

`~/.claude/scripts/issue-review-recon.sh` has **already run**, read-only. It resolved
the reviewer alias, detected the PR state, picked the branch of the workflow that
applies, and gathered the diff you need. Its output is below.

It ends with `IR-BRANCH: A | B | STOP` and `IR-RESULT: <STATUS>`. Everything you need
about worktree, PR, and diff state is in that output. Do not re-run `issue info`,
`gh pr view`, `git status`, `git log`, or `git diff` to orient yourself.

It deliberately did **not** commit, push, or run `issue review request` — those need
prose only you can write. That is the work left for you.

---

!`bash ~/.claude/scripts/issue-review-recon.sh "$ARGUMENTS" 2>&1 || true`

---

## Act on the result

| `IR-RESULT` | What to do |
|---|---|
| `READY` + `IR-BRANCH: A` | First review request — Branch A below. |
| `READY` + `IR-BRANCH: B` | Re-review after comments — Branch B below. |
| `NOTHING-NEW` | Tell the user there's nothing new to re-review. Stop. |
| `PR-MERGED` / `PR-CLOSED` | Report it; there's nothing to review. Stop. |
| `PROTECTED` | Report the branch and ask which worktree they meant. Stop. |
| `NOT-ISSUE-WORKTREE` | Report it. Ask whether to run from an issue worktree or supply title/body without the templates. Stop. |
| `UNKNOWN-REVIEWER` | Report the alias and the known ones, and ask. Stop. |
| `ERROR` | Read the message, fix the precondition, re-run the script. |

On `READY`, open the four steps of the branch named in `IR-BRANCH` as tasks —
`TaskCreate` one per step, `TaskUpdate` each to `in_progress` as you start it and
`completed` as it lands — then work them. If those tools are unavailable, keep the
four steps as a list in your replies; do not go looking for a tracking tool.

On any other result there is nothing to track — report and stop.

Stop and ask if any step below fails or is ambiguous — never force-push, never invent
a summary the diff doesn't support.

### Branch A — no PR yet

1. **Judge the work.** The diff is above. Confirm the change is actually complete and
   coherent before shipping it. Untracked files are listed separately — decide
   whether each belongs in the commit.
2. **Commit** anything pending with a conventional-commit message derived from the
   issue + diff. (`issue review request` pushes but does not commit.)
3. **Draft the PR title + body** with the **`/write` skill**. Leave the Linear id out
   of both — the `pr_title` / `pr_body` templates append the `[<ISSUE>]` suffix and the
   `Closes <ISSUE>` line from the worktree's issue record, and writing them yourself
   costs title budget the template accounts for.
4. **Ship it** with the command printed under `== next ==`, filling in the three
   placeholders. The trailing positional is the Slack body; the `review_request`
   template appends the PR URL, so don't paste the link into it.

   Add `--arg linear_magic_word=Ref` if this PR must **not** close the issue (partial
   work, one of several PRs) — it still links, but merging won't transition the issue.
   Other contributing words: `references`, `part of`, `related to`, `contributes to`,
   `towards`. Ask the user if it's unclear whether the PR closes the issue.

### Branch B — PR open, comments addressed

1. **Judge the work.** The diff above is scoped to what the reviewer has *not* seen
   (since their last review, or since the pushed tip if they haven't reviewed yet).
2. **Commit** anything pending with a conventional-commit message describing the
   review fixes.
3. **Summarize** with the **`/write` skill** — a tight 1–2 sentences on what changed,
   backed by that diff.
4. **Re-request** with the command printed under `== next ==`. No
   `--pr-title`/`--pr-body`; the PR already exists.

## Notes

- The subcommand is `issue review request`, not `issue review` — the latter is a
  command group and exits non-zero.
- `issue review request` posts the Slack DM itself when `SLACK_TOKEN` is configured.
  Without a token it prints a JSON **intent** (`slack_id`, `text`, `pr_url`, …) instead
  of sending — then send the DM yourself with `slack_send_message` to that `slack_id`
  (open the DM with `slack_create_conversation` if needed). The recon output shows the
  reviewer's `slack:` id.
- Never force-push. `issue review request` runs a plain `git push -u`; if the branch has
  diverged it fails — surface the error and ask, don't retry blindly.
- Override the GitHub handle or base only when needed: `--reviewer <gh-handle>`,
  `--base <branch>`. Skip the push with `--no-push`.
- Keep the Slack body in the user's voice — short, direct, no AI throat-clearing.
- If `issue review request` fails, show the exact error and stop.
