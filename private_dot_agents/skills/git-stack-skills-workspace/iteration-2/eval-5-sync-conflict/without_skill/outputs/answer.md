# `git-stack sync` stopped on a merge conflict — what to do

## Short version

This is expected. `git-stack sync` rebases your local branches on top of their pull
remotes, and a rebase **cannot** auto-resolve a real content conflict — only *you*
know which version is correct. git-stack hands control to a normal `git rebase` and
pauses. It has **not** failed or lost anything; it is mid-rebase, waiting for you to
resolve the conflict and continue.

## What's happening

`git-stack sync` is, under the hood, a `git rebase` (one per branch in the stack).
When git replays one of your commits onto the updated base and the same lines were
changed on both sides, it stops with conflict markers and a paused rebase. Your repo
is now in the "rebase in progress" state.

## Step-by-step recovery

1. See where you are and which files conflict:

   ```bash
   git status
   ```

   Conflicted files are listed under "Unmerged paths". You can also list just them:

   ```bash
   git diff --name-only --diff-filter=U
   ```

2. Open each conflicted file and resolve the `<<<<<<<` / `=======` / `>>>>>>>`
   markers, keeping the correct final content.

3. Mark each resolved file as done:

   ```bash
   git add <file>          # repeat per file, or:
   git add -A
   ```

4. Continue the rebase:

   ```bash
   git rebase --continue
   ```

   If the commit you just resolved became empty (its change is now already present
   upstream), git will tell you to skip it instead:

   ```bash
   git rebase --skip
   ```

5. There may be **more than one** conflict (multiple commits, multiple branches in
   the stack). Repeat steps 1–4 each time the rebase pauses, until git reports the
   rebase is complete.

6. Once the rebase finishes, re-run sync to let git-stack finish restacking the rest
   of your branches and confirm the stack is clean:

   ```bash
   git-stack sync
   ```

   Optionally view the result:

   ```bash
   git-stack --format graph
   ```

## If you want to bail out instead

To abandon the sync and put every branch back exactly where it was before you ran it:

```bash
git rebase --abort
```

`git rebase --abort` only undoes the single in-progress rebase. If git-stack had
already completed and rewrote earlier branches before stopping, the cleanest full
undo is git-stack's own backup:

```bash
git branch-stash pop
```

(`git-stack` automatically snapshots branch positions via `git branch-stash` before
it rewrites history, so this restores all branches at once.)

## Why git-stack doesn't "just handle it"

A merge conflict is a semantic decision, not a mechanical one — no tool can safely
pick which change wins. git-stack's job is to drive the rebases and remember where
every branch should land; resolving overlapping edits is the one step it correctly
leaves to you. After you resolve and `git rebase --continue`, git-stack picks the
stack back up automatically.

## Quick reference

```bash
git status                                # see conflicted files
git diff --name-only --diff-filter=U      # list only conflicts
# ...edit files, remove conflict markers...
git add -A                                # mark resolved
git rebase --continue                     # or: git rebase --skip
# repeat until rebase completes, then:
git-stack sync                            # finish restacking
# escape hatch:
git rebase --abort                        # undo the in-progress rebase
git branch-stash pop                      # restore all branch positions
```
