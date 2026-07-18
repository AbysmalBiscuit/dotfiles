---
name: git-stack-recover
description: >-
  Recover and repair a stacked-branch setup when something goes wrong: undo a
  `git-stack` history rewrite via `git branch-stash`, resolve the merge conflicts
  `git-stack` refuses to handle, and fix a stack that diverged or split (`git-stack
  --repair`) after a manual `git rebase` or a direct commit on a parent branch. Use
  this WHENEVER the user says a git-stack/stacked-branch operation "broke" / "messed
  up" / "lost my branches", wants to "undo a rebase or amend", hits a "conflict
  during git-stack", needs to "restore branch positions", asks about "branch-stash"
  / "git-stack --repair" / "diverged stack", or wants to inspect/fix protected-branch
  config. For the normal authoring loop use `git-stack-workflow`; for pushing use
  `git-stack-publish`.
---

# Recovering and repairing a stack

`git-stack` is built to fail safe: it defers permanent changes until an operation
succeeds and snapshots every branch's position before rewriting history. So most
"it broke" situations are recoverable. Diagnose which of three cases you're in:

1. A rewrite (sync / rebase / amend / reword) **completed but left branches
   where you didn't want** → undo with `git branch-stash`.
2. A rewrite **stopped on a merge conflict** → `git-stack` gave up; finish the
   rebase by hand.
3. The stack **diverged or split** (manual `git rebase`, or a commit landed
   directly on a parent) → `git-stack --repair`.

## Case 1 — undo a history rewrite with branch-stash

`git-stack` implicitly runs `git-branch-stash` before modifying branches, saving
each branch's commit position to `.git/branch-stash`. This is *not* `git stash`
(working tree) — it snapshots **where every branch points**.

**Critical detail:** `git-stack` writes its snapshots to a snapshot stack named
`git-stack`, **not** the `git-branch-stash` default stack (`recent`). So you must
name that stack on every undo command, or you'll be looking at an empty/unrelated
stack. git-stack's own success message tells you exactly this:
`To undo, run git branch-stash pop git-stack`.

```console
$ git-branch-stash list git-stack    # show git-stack's snapshots (NOT bare `list`)
$ git-branch-stash apply git-stack   # restore all branches to the last snapshot (kept)
$ git-branch-stash pop git-stack     # restore and delete the snapshot
```

Other operations (still pass the `git-stack` stack name to target git-stack's
snapshots):

```console
$ git-branch-stash push -m "before risky rebase" git-stack   # manual snapshot
$ git-branch-stash drop git-stack                            # delete the last snapshot
$ git-branch-stash stacks                                    # list all snapshot stacks
$ git-branch-stash clear git-stack                           # delete git-stack's snapshots
```

Workflow: `list git-stack` to confirm there's a pre-operation snapshot, `apply
git-stack` to restore, verify with `git-stack`, then `pop`/`drop` if you're happy.
Prefer `apply` over `pop` until you've confirmed the restore is what you wanted.
If you're unsure which stack holds your snapshot, `git-branch-stash stacks` lists
them all.

If there's no useful snapshot, fall back to `git reflog` and reset branches
manually — but branch-stash exists precisely to spare you that.

## Case 2 — a conflict stopped the operation

`git-stack` does **not** resolve merge conflicts. When a sync/rebase hits one, it
stops and hands control back to plain Git. Resolve it the normal way:

```console
$ git status                  # see the in-progress rebase and conflicted files
# ...edit files to resolve the conflicts...
$ git add <resolved-files>
$ git rebase --continue       # repeat until the rebase finishes
# or, to bail out entirely:
$ git rebase --abort
```

After finishing a manual `git rebase`, the stack's branches may now be split or
out of sync — continue to Case 3 to stitch it back together.

If you'd rather not deal with the conflict at all, `git rebase --abort` then
`git-branch-stash apply git-stack` returns you to the pre-operation state.

## Case 3 — repair a diverged or split stack

`git-stack --repair` cleans up stacks that drifted out of `git-stack`'s expected
shape:

- You committed **directly on a parent branch** → repair re-points the dependent
  stacks on top of that new commit.
- You ran a manual **`git rebase`** that split one stack into two → repair merges
  them back into a single stack.

```console
$ git-stack --repair -n       # dry-run: preview the repair
$ git-stack --repair          # fix diverging branches
$ git-stack --rebase --repair # rebase onto the protected base AND repair in one pass
```

`--repair` runs automatically during `--rebase` when `stack.auto-repair` is
enabled. After repairing, confirm with `git-stack` (and `git-stack --format
graph` for a fuller picture).

## Inspecting and fixing config when detection looks wrong

If `git-stack` rebased onto the wrong base or treated the wrong branches as
protected, the protected-branch config is usually the cause:

```console
$ git-stack --protected -v          # which branches are currently protected
$ git-stack --dump-config -         # full effective config (precedence-resolved)
$ git-stack --protect 'release/*'   # protect additional branches locally
```

Common fixes:
- A long-lived branch keeps getting rewritten → add it to `stack.protected-branch`
  (via `--protect <glob>`).
- Wrong remote being pulled/pushed → set `stack.pull-remote` / `stack.push-remote`
  (see **git-stack-publish**).
- Branches splitting off unexpectedly → check `stack.auto-base-commit-count` and
  the `stack.protect-commit-*` thresholds in the dumped config.

## Safety habits

- Reach for `--dry-run` / `-n` before any rewrite you're unsure about.
- Take a manual `git-branch-stash push -m "..." git-stack` before deliberately
  risky surgery, so you have a labelled restore point in the same stack git-stack
  uses.
- After any recovery, run `git-stack` to confirm the stack looks right before
  pushing (**git-stack-publish**).
