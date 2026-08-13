# Fixing the earliest commit and carrying the stack along

Good news: this is the exact case `git-stack` is built for. You change the
earliest commit and it rebases everything stacked on top for you — you do not
touch the upper commits by hand. The cleanest way to do it when the fix is
**already sitting in your working tree** and you're at the **top** of the stack
is the fixup workflow (no navigating up and down the stack).

## Your stack right now

I inspected the repo read-only. Here's what it looks like:

```
main                feat: add util module
 └─ feature-a       feat(user): add fetchUser   ← earliest commit, the one with the bug
     └─ (567271d)   refactor: extract helpers
         └─ feature-b   WIP: refactor helpers
             └─ feature-c   feat: new feature on top
```

The miscoded `fetchUser` lives in the earliest commit, which is the tip of
branch **`feature-a`**. Everything else is stacked above it. We'll fold your
working-tree fix into that commit and let `git-stack` restack the rest.

## The plan (recommended: fixup workflow)

This is the path the workflow skill recommends for "fix an earlier commit while
working at the top of the stack" — you never have to navigate.

```console
# 0. Look before you leap — confirm the stack and that your fix is in the tree
$ git-stack --show-commits all          # see the whole stack + which commit is the target
$ git status                            # confirm the corrected file is the only change
$ git diff                              # eyeball: fetchUser -> getUser

# 1. Stage your already-made fix
$ git add user.rs                       # or: git add -A  (stage only the fix)

# 2. Record a fixup aimed at the earliest commit (referenced by its branch)
$ git commit --fixup feature-a          # creates "fixup! feat(user): add fetchUser"

# 3. Preview, then fold it in and restack the commits above it
$ git-stack --rebase --fixup squash -n  # DRY RUN — shows the squash + restack, changes nothing
$ git-stack --rebase --fixup squash     # squashes the fixup into feature-a, rebases descendants

# 4. Verify the result
$ git-stack --show-commits all          # the fixup is gone; feature-a now has the correct code
$ git-stack run cargo check             # confirm every commit in the stack still builds
```

Why this works: `git commit --fixup feature-a` tags the change with the target
commit's subject. `git-stack --rebase --fixup squash` then **moves** that fixup
down next to `feature-a`, **squashes** it in, and automatically rebases
`567271d`, `feature-b`, and `feature-c` onto the rewritten commit — so the two
(here, three) commits above come along cleanly and keep their branch labels.

Note `git commit --fixup` lands the fixup on whatever branch you're currently
on; that's fine — step 3 relocates it to the target regardless of where it
started.

## Alternative: navigate + amend

If you'd rather edit the commit in place (and you don't mind moving HEAD), do
this instead of steps 1-3 above:

```console
$ git-stack previous --branch --stash   # move down to feature-a, stashing your WT fix
$ git stash pop                          # bring the fix back onto the earliest commit
$ git add user.rs
$ git-stack amend                        # meld the fix into feature-a, keep its message
                                          #   (descendants are rebased automatically)
```

`amend` retargets the children for you, same as the fixup path — it's just a
different route to the same result. The fixup workflow is usually smoother here
because your fix is *already* in the working tree and you're sitting at the top.

If you're already sitting on `feature-a` (HEAD on the earliest commit), it's even
simpler: `git add user.rs && git-stack amend`, then `git-stack run cargo check`.

## Two things to know

- **The `WIP:` commit on `feature-b` does not block this.** WIP only holds a
  branch back from `git-stack --push`; `--rebase` restacks it normally. You can
  reword it later before publishing.
- **If the rebase hits a conflict**, `git-stack` stops and hands you back to
  plain `git` — it won't resolve conflicts itself. Resolve the files, then
  `git add` + `git rebase --continue`. To bail out and return to the
  pre-operation state: `git rebase --abort` then
  `git-branch-stash apply git-stack` (git-stack snapshots branch positions
  before every rewrite). That's the git-stack-recover territory.

## Why not plain `git rebase -i`?

A manual interactive rebase to edit the earliest commit would detach the upper
branches and you'd have to re-point `feature-b`/`feature-c` yourself. `git-stack
amend` / `--rebase --fixup` preserve the inter-branch relationships
automatically, which is the whole point.
