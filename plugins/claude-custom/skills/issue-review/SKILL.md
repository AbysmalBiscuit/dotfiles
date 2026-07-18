---
name: issue-review
description: "Request (re-)review of the current issue worktree via `issue review` — push, open/reuse the PR, add the reviewer, and Slack them Use when the user invokes $issue-review or asks for this workflow."
---

# $issue-review

Hand a finished (or just-updated) issue worktree to a reviewer using `issue review`,
which does the mechanics for you: pushes the branch, opens **or** reuses the PR, adds
the GitHub reviewer, and Slacks them the body + PR link.

Run this from **inside the issue worktree**. `issue review` detects the PR state and
does the right thing — your job is to feed it a good PR title/body (first review) or a
tight summary of what changed (re-review), and to pick the reviewer.

## Reviewer

The reviewer is the **person alias** `<USER_INPUT>` (from `[people]` in devkit.toml),
or **`igor`** when that is empty. Resolve it once and substitute it for `<alias>` in
the commands below. Known aliases: `igor`, `theo`, `liza`, `arnaud`, `lev`. The alias
resolves to both the GitHub handle (for `--reviewer`) and the Slack user (for the DM);
you pass the alias to `--to`, not a raw id.

## Steps

Invoke the **`checklist` skill** first and track the steps for whichever branch below
applies. Stop and ask the user if any step fails or is ambiguous — never force-push,
never invent a summary you can't back with the diff.

### 1. Confirm context + detect PR state

- Confirm the cwd is an issue worktree on a feature branch (not `staging`/`main`):
  `git rev-parse --abbrev-ref HEAD`.
- Detect the PR for the current branch:

  ```bash
  gh pr view --json number,state,url,headRefName,reviewRequests,latestReviews 2>/dev/null
  ```

  A non-zero exit / empty output ⇒ **no PR** → go to **Branch A**.
  A PR in state `OPEN` ⇒ go to **Branch B**.
  A `MERGED`/`CLOSED` PR ⇒ stop and report; there's nothing to review.

  (`issue review` enforces the same rules — base-branch guard and merged/closed stop —
  so this is to pick the right inputs below, not to duplicate its logic.)

### Branch A — No PR yet (work just finished)

1. **Review the work.** Show `git status --short` and `git diff --stat` (plus the full
   diff if small). Confirm the change actually looks complete before shipping it.
2. **Commit** any pending work with a conventional-commit message derived from the
   issue + diff. If everything is already committed, skip. (`issue review` pushes but
   does **not** commit — commit first.)
3. **Draft the PR title + body.** Title is a conventional-commit subject; body is what
   changed + why, with the Linear issue link. Use the **`$write` skill** for the body.
4. **Ship it** — `issue review` pushes, opens the PR against the default base
   (`staging`), requests the reviewer, and DMs them:

   ```bash
   issue review --to "<alias>" \
     --pr-title "<conventional-commit title>" \
     --pr-body  "<what changed + why + Linear link>" \
     "<one-line Slack ask, e.g. opened the PR for <issue>, mind reviewing? 🙏>"
   ```

   The trailing positional is the Slack body; the default `slack` template appends the
   PR URL, so don't paste the link into it yourself.

### Branch B — PR exists, changes made to address comments

1. **Confirm there are new changes.** There must be something new to re-review —
   uncommitted changes, unpushed commits, or commits newer than the reviewer's last
   review:

   ```bash
   git status --short
   git log --oneline @{u}..HEAD 2>/dev/null   # unpushed commits
   ```

   If nothing is pending and HEAD is already what they last reviewed, tell the user
   there's nothing new to re-review and stop.
2. **Commit** the pending changes (conventional-commit message describing the review
   fixes) so the PR reflects the addressed comments. `issue review` will push them.
3. **Summarize what changed.** Gather the diff that addresses the comments — the
   commits since the reviewer's last review:

   ```bash
   git log --reverse --format='%s%n%b' <last-reviewed-sha>..HEAD
   git diff <last-reviewed-sha>..HEAD
   ```

   Then use the **`$write` skill** to produce a tight **1–2 sentence** summary.
4. **Re-request the review** — on an OPEN PR `issue review` adds the reviewer back and
   DMs them the summary:

   ```bash
   issue review --to "<alias>" \
     "addressed your comments: <1–2 sentence summary>. Mind taking another look? 🙏"
   ```

   No `--pr-title`/`--pr-body` needed — the PR already exists.

## Notes

- `issue review` posts the Slack DM itself when `SLACK_TOKEN` is configured. If it has
  no token it prints a JSON **intent** (`slack_id`, `text`, `pr_url`, …) instead of
  sending — in that case send the DM yourself with `slack_send_message` to that
  `slack_id` (open the DM with `slack_create_conversation` if needed).
- Never force-push. `issue review` runs a plain `git push -u`; if the branch has
  diverged it fails — surface the error and ask, don't retry blindly.
- Override the GitHub handle or base only when needed: `--reviewer <gh-handle>`,
  `--base <branch>`. Skip the push with `--no-push`.
- Keep the Slack body in the user's voice — short, direct, no AI throat-clearing. The
  `$write` skill output is the body; don't pad it.
- If `issue review` fails, show the exact error and stop.
