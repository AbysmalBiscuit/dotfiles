# Fixing the earliest commit in your stack

You're 3 commits deep, the bug is in the **earliest** commit (the root of the
stack), and the corrected file is already sitting unstaged in your working tree.
With `git-stack` you don't rebase by hand — you stage the fix, meld it into that
earliest commit, and `git-stack` automatically rebases the two commits stacked on
top onto the rewritten version. As long as the fix doesn't textually collide with
those two commits (a function rename almost never does), they come along cleanly.

> Plan only — nothing below has been run against your repo. Run these yourself.

## Recommended: amend the earliest commit directly (no navigating)

`git-stack amend [REV]` melds your **staged** changes into any commit you name,
not just `HEAD`, and then rebases all descendants on top of it. So you can stay
right where you are at the top of the stack.

```console
# 1. See the stack and confirm which commit is the earliest one.
#    The earliest (bottom) commit is the root of the stack; with 3 commits it's HEAD~2.
$ git-stack --show-commits all

# 2. (Optional but cheap insurance) snapshot every branch position so the
#    rewrite is trivially undoable.
$ git-branch-stash push -m "before fixup of getUser rename"

# 3. Stage the already-fixed file from your working tree.
$ git add path/to/the/file        # or: git add -A

# 4. Dry-run the amend to preview the rewrite + descendant rebase.
$ git-stack amend HEAD~2 -n

# 5. Meld the staged fix into the earliest commit; the two commits on top
#    are rebased onto the corrected commit automatically.
$ git-stack amend HEAD~2

# 6. Verify the stack looks right and every commit still builds.
$ git-stack --show-commits all
$ git-stack run cargo check        # swap in your project's build/test command
```

Notes:
- `HEAD~2` is the earliest of three commits. If you'd rather not count, copy the
  short SHA of the bottom commit from the `git-stack --show-commits all` output
  and use that as the REV — e.g. `git-stack amend <sha>`.
- Keep the message as-is (it stays the same by default). If the commit's message
  also mentioned `fetchUser`, add `-e` to edit it: `git-stack amend HEAD~2 -e`.
- Don't use `git-stack amend -a` here unless you want **all** changed files
  folded in; staging the one fixed file in step 3 keeps the amend scoped.

## Alternative: the fixup workflow

Same result, recording an explicit `fixup!` commit first. Useful if you want a
visible intermediate state before squashing.

```console
$ git-stack --show-commits all              # find the earliest commit's SHA
$ git add path/to/the/file                  # stage the fix
$ git commit --fixup <sha-of-earliest>      # records "fixup! <its subject>"
$ git-stack --rebase --fixup squash -n      # preview: fold fixup in + restack
$ git-stack --rebase --fixup squash         # squash into target, rebase the two on top
$ git-stack --show-commits all              # verify
```

## Alternative: navigate, then amend HEAD

If you prefer to be sitting on the commit you're editing:

```console
$ git-stack previous 2 --stash    # move HEAD back to the earliest commit (stash WT first)
$ git stash pop                   # bring the fix back into the working tree
$ git add path/to/the/file
$ git-stack amend                 # amends HEAD (now the earliest commit); descendants rebase
$ git-stack next 2                # return to the top of the stack
$ git-stack --show-commits all
```

## If something goes sideways

- **A conflict stops the rebase** (`git-stack` won't resolve conflicts): finish
  it with normal Git — edit the file, `git add`, `git rebase --continue` — or
  bail with `git rebase --abort`.
- **The result isn't what you wanted**: undo the whole rewrite with the snapshot
  from step 2 — `git-branch-stash apply` (restores every branch position;
  re-run, then `git-branch-stash pop`/`drop` once happy).

## Why this works

`git-stack` treats the rewrite of the earliest commit as the source of truth and
re-points the two stacked commits/branches onto the corrected commit for you —
no manual `git rebase --onto`, and the inter-commit relationships are preserved.
The only case needing hands-on work is a textual conflict, which a `fetchUser` →
`getUser` rename in a single commit won't normally produce.
