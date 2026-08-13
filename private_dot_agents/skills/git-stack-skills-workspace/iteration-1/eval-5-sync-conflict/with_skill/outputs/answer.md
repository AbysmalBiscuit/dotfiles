# `git-stack sync` stopped on a merge conflict — what to do

This is expected behavior, not a bug. **`git-stack` deliberately does not resolve merge conflicts.** When `sync` rebases your development branches onto the updated protected base and a conflict appears, it stops and hands control back to plain `git rebase`. You finish the rebase by hand, and `git-stack` resumes managing the stack once the tree is clean again.

## 1. See where you are (read-only)

```console
git status
```

Look for `interactive rebase in progress` (or `rebase in progress`) and the list of conflicted (`both modified`) files.

## 2. Resolve and continue the rebase

```console
# ...edit each conflicted file to resolve the conflict markers...
git add <resolved-files>
git rebase --continue
```

Repeat the edit → `git add` → `git rebase --continue` loop for every commit that conflicts until the rebase reports it has finished. You may hit several conflict stops in one sync — that is normal when multiple commits touch the same lines.

## 3. If you'd rather not deal with it right now — bail out cleanly

```console
git rebase --abort        # cancel the in-progress rebase
git-branch-stash apply    # restore every branch to its pre-sync position
```

`git-stack` snapshots where every branch points (via `git-branch-stash`, in `.git/branch-stash`) before it rewrites history, so aborting and applying the snapshot returns you to exactly the state you were in before `sync`. You can then retry later.

## 4. After the rebase finishes — verify, and repair if needed

```console
git-stack                 # confirm the stack looks right
git-stack --format graph  # fuller picture if anything looks off
```

A manual `git rebase --continue` can leave the stack split or diverged (branches no longer stitched into one stack). If `git-stack` shows that, stitch it back together:

```console
git-stack --repair -n     # preview the repair
git-stack --repair        # re-merge the diverged/split branches
```

## Why git-stack "didn't handle it"

`git-stack` automates the rebase *micromanagement* (which branch goes onto which base, retargeting children, force-pushing), but resolving the actual textual conflict requires your judgment about which change wins — so it stops and defers to `git`. Running `sync` regularly is in fact how you surface these conflicts early, while they're small.

## Quick reference

| Situation | Command |
|-----------|---------|
| Inspect the stuck state | `git status` |
| Resolve a conflicted file | edit it, then `git add <file>` |
| Continue after resolving | `git rebase --continue` |
| Give up on this conflict | `git rebase --abort` then `git-branch-stash apply` |
| Check the stack afterward | `git-stack` / `git-stack --format graph` |
| Fix a split/diverged stack | `git-stack --repair` (preview with `-n`) |

Note: in the current checkout there is no rebase in progress (`git status` shows a clean tree on `main`), so the commands above are the procedure to apply when the conflict actually occurs — none of them have been run.
