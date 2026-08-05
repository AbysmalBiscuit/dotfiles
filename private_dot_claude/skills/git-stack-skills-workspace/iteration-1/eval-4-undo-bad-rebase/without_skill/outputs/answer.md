# Undoing a bad `git-stack` rebase

Good news: you haven't pushed, and `git-stack` automatically snapshots every branch position **before** it rewrites anything. So this is recoverable. You have two independent safety nets — a `git-stack` one (clean, preferred) and a plain-git one (always works as a fallback).

Don't run any more `git-stack` commands until you've recovered, and don't run `git gc` — that's what could eventually drop the old commits.

---

## Option A — restore from `git-stack`'s branch-stash (preferred)

Before any history rewrite (rebase/sync/restack), `git-stack` saves a snapshot of **all** your branch positions into a stash. You can list those snapshots and pop the most recent one to put every branch back exactly where it was.

**1. Inspect what snapshots exist (read-only):**

```bash
git branch-stash list
```

You'll see one entry per snapshot, newest first, with a message and timestamp. The top entry (`stash@{0}` / the most recent) is the one taken right before the rebase you want to undo.

**2. Restore all branches to the snapshot:**

```bash
git branch-stash pop
```

This resets every branch back to its recorded position in one shot — including the feature branch that ended up in the wrong place. (`pop` applies the newest snapshot and removes it from the list. If you'd rather keep the snapshot around while you check the result, use `git branch-stash apply` instead — same effect, but it leaves the entry in the list.)

**3. Verify:**

```bash
git stack          # view the stack as git-stack sees it
git log --oneline --graph --all --decorate   # confirm branch tips
```

If the branches are back where you expect, you're done.

> Note: `branch-stash` only restores **branch pointers** (ref positions). It does not touch your working tree or index. Commit or stash any uncommitted work first so nothing is lost when refs move.

---

## Option B — fallback via the reflog (always works)

If `branch-stash list` is empty, doesn't show the pre-rebase state, or you just want to recover one specific branch, use git's reflog. The rebase moved the branch but the old commit is still in the reflog.

**1. Find where the branch used to point:**

```bash
git reflog show <feature-branch>
```

Read down the list to the entry just **before** the rebase (it'll be the line right above the `rebase`/`rebase (finish)` entries). Note its commit SHA — call it `<good-sha>`. You can sanity-check it without moving anything:

```bash
git log --oneline -5 <good-sha>
git log --oneline -5 <feature-branch>@{1}    # @{1} = "one move ago", often exactly the pre-rebase tip
```

**2. Move the branch back to that commit:**

```bash
git branch -f <feature-branch> <good-sha>
```

Use `git branch -f` (not `reset --hard`) when you're sitting on a *different* branch — it repositions the target branch without disturbing your checkout. If you currently have `<feature-branch>` checked out, use:

```bash
git switch <feature-branch>
git reset --hard <good-sha>
```

(`reset --hard` will overwrite your working tree, so commit/stash first.)

**3. Repeat for any other branch the rebase moved**, then re-check positions:

```bash
git log --oneline --graph --all --decorate
```

---

## After recovery

- Run `git stack` to confirm the stack structure looks right.
- If the stack metadata looks confused even though the branches are back in place, `git stack --repair` realigns/relinks branches in the stack without rewriting commit history. (Read-only preview isn't available, so only run it once branches are positioned correctly.)
- When you re-run the rebase/sync, do it deliberately — e.g. check the stack with `git stack` first, and consider rebasing one branch at a time so you can spot a wrong move immediately.

---

## TL;DR

```bash
git branch-stash list     # see pre-rebase snapshots
git branch-stash pop      # restore ALL branches to the pre-rebase state
git stack                 # verify
```

If that list is empty, fall back to:

```bash
git reflog show <feature-branch>          # find <good-sha> before the rebase
git branch -f <feature-branch> <good-sha> # move it back
```

Since nothing was pushed, no force-push or remote cleanup is needed — this is purely a local ref fix.
