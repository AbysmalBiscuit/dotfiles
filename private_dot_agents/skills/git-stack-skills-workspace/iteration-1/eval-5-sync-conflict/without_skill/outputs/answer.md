# `git-stack sync` stopped on a merge conflict — what to do

## Short version

This is expected. **Conflict resolution is an explicit non-feature of `git-stack`.** From its own README:

> Non-features — Conflict resolution: `git-stack` will give up and you'll have to use `git rebase` yourself to resolve the conflict.

`git-stack` does its restacking with an *in-memory* rebase. The moment a commit doesn't apply cleanly it **gives up on that branch**, reports something like `Failed to re-stack branch <name>` (and lists any blocked dependents), and leaves the rest of your stack as-is. It does **not** resolve the conflict for you, and it does **not** stop in the middle of a partially-rewritten history — by design it defers all permanent changes to the end, so you're left in a safe, consistent state.

So "it stopped partway with a merge conflict" really means: *one branch in the stack couldn't be rebased cleanly, and you need to do that one rebase by hand.* After that, re-run sync.

## Step 1 — See where you stand (read-only)

```bash
git status            # is a real rebase in progress, or is the tree clean?
git stack             # view the stack; the un-moved branch is the one that conflicts
git rev-parse --abbrev-ref HEAD
```

Two cases:

- **Tree is clean, no rebase in progress** (the usual case): `git-stack` backed out and left you where you started. There are no conflict markers to fix right now — you just need to perform the failing rebase manually (Step 2).
- **A `git rebase` is genuinely in progress** (`git status` says "interactive rebase in progress" / shows `both modified:` files): resolve it as a normal git rebase (Step 3), since one is already underway.

## Step 2 — Rebase the conflicting branch yourself

Check out the branch that failed to move and rebase it onto its intended base (the protected branch you sync against, usually `main`/`master`, or its parent branch in the stack):

```bash
git switch <conflicting-branch>
git rebase <base-branch>        # e.g. git rebase main, or the parent branch in the stack
```

Rebase bottom-up: do the branch closest to the base first, then each child onto its (now-rebased) parent.

## Step 3 — Resolve the conflict (standard git)

```bash
# edit each conflicted file, removing <<<<<<< ======= >>>>>>> markers
git add <resolved-files>
git rebase --continue           # repeat until the rebase finishes

# escape hatches:
git rebase --skip               # drop the current commit if appropriate
git rebase --abort              # bail out and return to pre-rebase state
```

`git diff --name-only --diff-filter=U` lists the still-conflicted files; a mergetool (`git mergetool`) also works.

## Step 4 — Let git-stack re-knit the stack and finish the sync

After the manual rebase, branch positions in the stack may be out of date. Repair them, then sync again:

```bash
git stack --repair      # re-detect parent/child relationships after your manual rebase
git stack sync          # finish syncing the rest of the stack
git stack               # confirm the stack looks right
```

`--repair` is exactly for "I rebased a branch by hand, fix up the stack to match."

## If you'd rather undo and start over

`git-stack` backs up your branch state before rewriting history. If a sync run left things in a state you don't like, restore the previous branch positions with:

```bash
git branch-stash pop git-stack
```

(`git-stack` prints a `To undo, run git branch-stash pop git-stack` hint after operations that rewrote history. This requires the `git-branch-stash` companion tool, which ships with git-stack.)

## Why this happens (so it's not a surprise next time)

- `git-stack` deliberately doesn't own a conflict-resolution UX — it hands conflicts back to plain `git rebase`, which you already know.
- It only *has* to deal with a conflict when history it's replaying onto an updated base genuinely overlaps your changes (e.g. an upstream PR got merged that touches the same lines).
- Everything else in the stack that *can* be rebased cleanly still gets moved; only the conflicting branch and its descendants are left for you.

### TL;DR command sequence

```bash
git status && git stack                 # inspect
git switch <conflicting-branch>
git rebase <base-or-parent-branch>      # resolve markers, git add, git rebase --continue
git stack --repair                      # fix stack metadata
git stack sync                          # finish
# or, to bail entirely:  git branch-stash pop git-stack
```
