# `git-stack sync` stopped on a merge conflict — what now

## The short version

This is expected behavior, not a bug. `git-stack` does **not** resolve merge
conflicts. When `sync` rebases your dev branches onto the updated protected base
and hits a conflict, it stops and hands control back to plain `git rebase`. You
finish the rebase by hand, and `git-stack` picks the stack back up from there.

The good news: before it rewrote anything, `git-stack` snapshotted every
branch's position (via `git branch-stash`, under the stack named `git-stack`),
so you can bail out cleanly at any point.

## Step 1 — see where you are (read-only)

```console
$ git status                 # shows the in-progress rebase + conflicted files
$ git-stack --format graph   # see the stack's current shape
```

You're now in a normal interrupted `git rebase`. Pick one of the two paths
below.

## Step 2a — resolve the conflict and continue (the usual choice)

```console
$ git status                 # list the conflicted files
# ...edit each conflicted file to resolve the <<<<<<< / ======= / >>>>>>> markers...
$ git add <resolved-files>   # stage each file as you fix it
$ git rebase --continue      # advance the rebase
```

Repeat (resolve -> `git add` -> `git rebase --continue`) for every commit that
conflicts until the rebase completes. A single `sync` can stop multiple times;
that's normal.

When the rebase finishes, confirm the stack looks right:

```console
$ git-stack                  # verify branch positions
$ git-stack --format graph   # fuller picture
```

## Step 2b — bail out instead (if you'd rather not deal with it now)

```console
$ git rebase --abort                   # stop the in-progress rebase
$ git branch-stash apply git-stack     # restore branches to their pre-sync positions
```

Note the explicit `git-stack` stack name — `git-stack` stores its automatic
snapshots there, not in the default `recent` stack, so a bare
`git branch-stash apply` would look at the wrong snapshot. Use `apply` (not
`pop`) so the snapshot is kept until you've confirmed the restore, then
`git branch-stash pop git-stack` once you're happy. You can inspect first with
`git branch-stash list git-stack`.

## Step 3 — after a manual rebase, check the stack is still stitched together

Finishing the rebase by hand can leave the stack split or diverged. Once your
working tree is clean, re-knit it:

```console
$ git-stack --repair -n      # dry-run: preview the repair
$ git-stack --repair         # re-merge any split/diverged branches
$ git-stack                  # final sanity check
```

## Why this happened (so it's less surprising next time)

`sync` deliberately does no "auto" magic and surfaces merge/semantic conflicts
early — that's the point of running it at the start of a session and before
pushing. Conflict resolution is the one thing `git-stack` leaves to you and
plain Git; everything around it (snapshotting, retargeting child branches,
repair) it still handles.

Current state in this repo: working tree is clean and no rebase is in progress,
so the conflict was already either resolved or aborted — if you didn't finish it
on purpose, run `git status` and `git-stack` to confirm the stack is where you
expect before pushing.
