---
name: migration-review
description: "Ship a kysely-sweep migration for review — open the PR or ping Igor to re-review after addressing comments Use when the user invokes $migration-review or asks for this workflow."
---

# $migration-review

Hand a finished (or just-updated) kysely-migration worktree to **Igor** for review.

Run this from **inside the issue worktree**. The command figures out whether the PR
exists yet and does the right thing:

- **No PR yet** (work just finished) → commit, push, open the PR, request Igor's
  review, and DM him on Slack to review it.
- **PR exists and changes were made to address review comments** → push the changes,
  write a short summary of what changed, re-request Igor's review, and DM him the
  summary asking for a re-review.

## Reviewer identity (Igor)

- **GitHub:** `igoradaptyv`
- **Slack:** user `U06HMNJB6KS` (igor@adaptyvbio.com)

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

### Branch A — No PR yet (work just finished)

1. **Review the work.** Show `git status --short` and `git diff --stat` (plus the full
   diff if small). Confirm the change actually looks complete before shipping it.
2. **Commit.** Stage and commit with a conventional-commit message derived from the
   issue + diff (e.g. `refactor(api): migrate <endpoint> ServiceContext to kysely`).
   If everything is already committed, skip.
3. **Push.** `git push -u origin "$(git rev-parse --abbrev-ref HEAD)"`.
4. **Open the PR**, basing on `staging` and requesting Igor:

   ```bash
   gh pr create --base staging --reviewer igoradaptyv \
     --title "<conventional-commit title>" \
     --body  "<what changed + why, and the Linear issue link>"
   ```

   Capture the PR URL from the command output.
5. **Slack Igor.** DM `U06HMNJB6KS` a short message with the PR link asking him to
   review (use `slack_send_message`; open the DM with `slack_create_conversation` if
   needed). Keep it one line, e.g.:
   `Hey Igor — opened <PR url> (kysely migration for <issue>). Could you review when you get a chance? 🙏`

### Branch B — PR exists, changes made to address comments

1. **Confirm there are new changes.** There must be something new to re-review —
   uncommitted changes, unpushed commits, or commits newer than Igor's last review:

   ```bash
   git status --short
   git log --oneline @{u}..HEAD 2>/dev/null   # unpushed commits
   ```

   If nothing is pending and HEAD is already what Igor last reviewed, tell the user
   there's nothing new to re-review and stop.
2. **Commit + push** the pending changes (conventional-commit message describing the
   review fixes), so the PR reflects the addressed comments.
3. **Summarize what changed.** Gather the diff that addresses the comments — the
   commits since Igor's last review:

   ```bash
   git log --reverse --format='%s%n%b' <last-reviewed-sha>..HEAD
   git diff <last-reviewed-sha>..HEAD
   ```

   Then invoke the **`$write` skill** to produce a tight **1–2 sentence** summary of
   what was changed to address the review.
4. **Re-request Igor's review** on the PR:

   ```bash
   gh pr edit --add-reviewer igoradaptyv
   ```

5. **Slack Igor** the summary with the PR link, asking for a re-review (use
   `slack_send_message` to `U06HMNJB6KS`), e.g.:
   `Hey Igor — addressed your comments on <PR url>: <1–2 sentence summary>. Mind taking another look? 🙏`

## Notes

- Never force-push. If the branch has diverged, surface it and ask.
- Keep the Slack message to the user's voice — short, direct, no AI throat-clearing.
  The `$write` skill output is the body; don't pad it.
- If `gh` or the Slack send fails, show the exact error and stop — don't retry blindly.
