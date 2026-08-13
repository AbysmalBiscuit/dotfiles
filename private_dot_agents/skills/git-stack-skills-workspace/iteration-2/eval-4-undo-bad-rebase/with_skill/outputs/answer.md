# Undoing a bad `git-stack` rebase

Good news: you haven't pushed, and `git-stack` is built to fail safe. Before
**every** history rewrite (sync / rebase / amend / reword) it auto-snapshots
where each branch points, so the normal fix is a one-liner. The catch most people
hit: `git-stack` stores those snapshots under a stack named **`git-stack`**, not
the `git-branch-stash` default (`recent`) — so you must name that stack on every
command or you'll be staring at an empty list.

## Step 1 — Confirm the snapshot exists (read-only, safe)

```console
$ git-branch-stash list git-stack     # the pre-rebase snapshot should be here
$ git-branch-stash stacks             # lists all snapshot stacks if you're unsure
```

## Step 2 — Restore your branches

```console
$ git-branch-stash apply git-stack    # move every branch back to its pre-rebase position (keeps the snapshot)
$ git-stack --show-commits all        # verify the stack looks like it did before
$ git-branch-stash pop git-stack      # once you're happy, re-apply + drop the snapshot
```

Use `apply` first (it leaves the snapshot in place) and only `pop` after you've
eyeballed the result with `git-stack`. `pop` = apply + delete in one go.

## IMPORTANT — what I actually found in this repo

I inspected your repo read-only (`git-branch-stash list git-stack`,
`git-branch-stash stacks`, and the reflogs). Two findings change the plan:

1. **There is no `git-stack` snapshot present.** `git-branch-stash list git-stack`
   is empty, `stacks` shows only `recent` (also empty), and there's no
   `.git/branch-stash` file. So Steps 1-2 above have nothing to restore from
   *right now* — that's the procedure to use, but the snapshot isn't there.
2. **No rebase appears in any reflog.** Every entry in `HEAD`, `feature-a`,
   `feature-b`, and `feature-c` reflogs is a plain `commit` or `checkout` /
   `branch: Created from HEAD` — there is no `rebase` event anywhere. The
   branches are sitting at the positions they were *built* at:

   ```
   main       a6845ec  feat: add util module        (protected base)
   feature-a  45f7b5b  feat(user): add fetchUser     -> on main
   feature-b  d66fee7  WIP: refactor helpers          -> on 567271d "refactor: extract helpers" -> on feature-a
   feature-c  c6a59ca  feat: new feature on top        -> on feature-b
   ```

So no history-rewriting `git-stack` rebase has actually landed here, and no
auto-snapshot was created. Before doing anything destructive, double-check
*which* branch you think is misplaced against the layout above — it may be that
the rebase you ran was a no-op (already in place), or that it failed/aborted
before rewriting anything.

## Step 3 (fallback) — if there's genuinely no snapshot: use the reflog

When `git-branch-stash` has no `git-stack` snapshot, reset each branch by hand
using its reflog (this is exactly the fallback the recovery skill points to).
First read where each branch used to point, **then** reset:

```console
$ git reflog show feature-b            # find the SHA the branch had BEFORE the move
$ git switch feature-b
$ git reset --hard feature-b@{1}       # @{1} = its previous position (pick the right entry)
```

Repeat per branch, working from the base of the stack upward, then run
`git-stack --repair` to stitch the inter-branch relationships back together:

```console
$ git-stack --repair -n                # preview the repair
$ git-stack --repair                   # re-point dependent branches correctly
$ git-stack --show-commits all         # confirm
```

In *this* repo, though, the reflogs show no prior (pre-rebase) position to roll
back to — each branch's `@{1}` is just "Created from HEAD" or an earlier commit
of its own, not a different base. So there is nothing to undo via reflog either.

## Bottom line

- **The right tool for "undo a bad git-stack rebase" is**
  `git-branch-stash apply git-stack` then `pop git-stack` — always with the
  `git-stack` stack name.
- **But in your current repo there is no snapshot and no rebase in the reflog**,
  so there is nothing to undo yet. Re-run the rebase if you still need it, and
  before it rewrites history confirm the snapshot lands:
  `git-branch-stash list git-stack` should show a new entry afterward.
- **Act before running another `git-stack` command.** Snapshots are created at
  the start of each op; running more git-stack operations can roll the snapshot
  you need out of reach. If you're about to do risky surgery, take a manual
  labelled restore point first:
  `git-branch-stash push -m "before rebase" git-stack`.
- You haven't pushed, so nothing here touches the remote — all of this is local
  and reversible.
