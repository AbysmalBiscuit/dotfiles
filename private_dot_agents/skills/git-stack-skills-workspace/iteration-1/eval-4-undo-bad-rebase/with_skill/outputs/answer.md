# Undo a bad `git-stack` rebase

Good news: this is the easy case. `git-stack` takes a **branch-stash snapshot of where every branch points right before it rewrites history**, so a rebase that moved your branches somewhere unexpected is undoable without touching the reflog. You haven't pushed, so there's nothing remote to unwind either — this is purely local.

`git-branch-stash` is *not* `git stash`. `git stash` saves your working-tree changes; `git-branch-stash` snapshots **where each branch points**. That's exactly what a bad rebase clobbered, and exactly what you'll restore.

## Recovery steps

### 1. Look before you leap (read-only)

```console
$ git status              # confirm no rebase is mid-flight and the tree is clean
$ git-stack               # see where the stack sits now (the "wrong" state)
$ git-branch-stash list   # confirm there's a pre-rebase snapshot (newest = top)
```

The top entry in `git-branch-stash list` is the snapshot `git-stack` took immediately before the rebase you want to undo. If you see it, you're set.

### 2. Restore branch positions

```console
$ git-branch-stash apply  # move all branches back to the snapshot (snapshot kept)
```

`apply` (not `pop`) is deliberate: it restores the branches **but keeps the snapshot**, so if the restore isn't quite right you can try again or fall back to the reflog.

### 3. Verify the stack is back

```console
$ git-stack                    # the misplaced feature branch should be home again
$ git-stack --format graph     # fuller picture if you want to double-check the shape
```

### 4. Once you're happy, clean up

```console
$ git-branch-stash pop    # re-apply + delete the snapshot, OR:
$ git-branch-stash drop   # just delete the snapshot you already applied
```

Only do step 4 after step 3 confirms everything is where it should be.

## If `git-branch-stash list` is empty or the top snapshot looks wrong

The snapshot is your clean path, but it's not the only one. Fall back to the reflog and reset the one branch by hand:

```console
$ git reflog show <feature-branch>          # find the SHA it pointed at pre-rebase
$ git switch <feature-branch>
$ git reset --hard <good-sha>               # move the branch back
$ git-stack --repair -n                     # preview re-stitching dependents
$ git-stack --repair                         # re-point dependent branches onto it
```

`--repair` re-merges any dependent branches that got split off when you hand-reset one branch in the stack.

## Notes

- **Don't run `git-stack sync` or `git-stack --rebase` first** — they rewrite history again and take a *new* snapshot, pushing the good pre-rebase snapshot further down the stack (and a fresh sync could re-introduce the same bad move). Restore first, investigate after.
- I checked this repo: the working tree is clean, no rebase is in progress, and the `recent` branch-stash stack currently has no snapshots here — so run `git-branch-stash list` in **your** repo to confirm the pre-rebase snapshot is present before applying.
- After you're restored, if the rebase moved things wrong because `git-stack` picked the wrong base or treated a branch as (un)protected, check `git-stack --protected -v` and `git-stack --dump-config -` before re-running the rebase, so it doesn't repeat the mistake.

I have not run any mutating commands — everything above is for you to run after eyeballing the `git-branch-stash list` output.
