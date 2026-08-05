# Undoing a bad `git-stack` rebase

Good news: you haven't pushed, and Git keeps the old commits in the reflog (default 90 days), so nothing is actually lost. We just need to point your branches back at their pre-rebase tips.

I inspected your repo (read-only) before writing this. Current state:

```
main      a6845ec
feature-a 45f7b5b   (checked out)
feature-b d66fee7
feature-c c6a59ca
```

Work top-down: **branch-stash first, reflog as the reliable fallback.**

---

## Option 1 (try first): restore from the branch-stash snapshot

`git-stack` takes a snapshot of every branch position *before* it rewrites history, and that snapshot is its built-in undo. Restore it with the `git-branch-stash` tool:

```bash
git branch-stash list          # newest snapshot at the top = your pre-rebase state
git branch-stash pop           # restore ALL branches to that snapshot and remove it
# or, to restore but keep the snapshot:
git branch-stash apply
```

`pop`/`apply` move every branch tip back at once, which is exactly what you want for a stack.

> Heads up: I checked your repo and `git branch-stash list` is currently **empty** — there is no stored snapshot right now. So this option likely won't help here, and you should use Option 2.

---

## Option 2 (reliable here): restore each branch from its reflog

Every branch tip remembers its history. Inspect each feature branch and find the entry from **before** the rebase (use the timestamps / the commit subject you recognize):

```bash
git reflog show feature-a
git reflog show feature-b
git reflog show feature-c
```

The rebase appears as the most recent entry (`@{0}`); the line just below it (older timestamp) is the pre-rebase tip. Move each branch back to that entry.

For branches that are **not** checked out, use `git branch -f` (no checkout needed):

```bash
# replace {N} with the pre-rebase entry number you identified above
git branch -f feature-b feature-b@{N}
git branch -f feature-c feature-c@{N}
```

For the branch you currently have checked out (`feature-a`), use reset instead:

```bash
git switch feature-a
git reset --hard feature-a@{N}
```

### Shortcut for the branch you were on during the rebase

The rebase saved that branch's old tip to `ORIG_HEAD`:

```bash
git reset --hard ORIG_HEAD     # only restores the currently checked-out branch
```

Handy for the one branch, but you still need the reflog steps above to fix the rest of the stack.

---

## After restoring: re-knit and verify the stack

Once the tips are back where they belong, let `git-stack` re-detect the parent/child links and confirm the layout:

```bash
git-stack --repair     # rebuilds stack relationships without rewriting your commits
git-stack              # view the stack and confirm everything is where you expect
```

---

## Don't do these until you've confirmed recovery

- Don't `git push` / force-push — keep the bad state local.
- Don't run `git gc --prune=now` or `git reflog expire` — that's what would actually destroy the recoverable old commits.
- Don't run another `git-stack` rebase/sync until the branches are back in place.

### How to find a lost commit if a reflog entry is unclear

```bash
git reflog --date=iso          # all HEAD movements with timestamps
git log --graph --oneline --all # see where every branch currently points
```

If you can identify the right commit SHA directly, you can skip the `@{N}` syntax and use the SHA: `git branch -f feature-b <sha>`.
