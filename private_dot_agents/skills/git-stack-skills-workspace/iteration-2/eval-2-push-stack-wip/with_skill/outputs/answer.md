# Pushing your stack and opening PRs

Short version: with `git-stack --push`, **only `feature-a` will actually be pushed** right now. `feature-b` and `feature-c` are deliberately held back. Here is the plan and the why.

## What I verified in your repo (read-only)

`git-stack --show-commits all` shows:

```
main (no remote) feat: add util module
⌽ feature-a (ready) feat(user): add fetchUser
⌽ 567271d         refactor: extract helpers
⌽ feature-b        WIP: refactor helpers
⌽ feature-c        feat: new feature on top
```

`git-stack --push -n` (dry run) confirms only **`feature-a`** carries the `(ready)` marker.

## What `git-stack --push` does and why

`git-stack --push` force-pushes (with lease) only the **ready** development branches to `stack.push-remote` and sets their upstream. A branch is "ready" only when BOTH hold:

1. **It is not stacked on top of another development branch** — only the root-of-stack branch (the one sitting directly on the protected base `main`) is ready. Branches higher in the stack are held back on purpose.
2. **It has no WIP commits.** A commit is WIP if its summary is exactly `WIP` or starts with `WIP:`, `draft:`, `Draft:`, `wip `, or `WIP `.

Applied to your stack:

| Branch | Pushed? | Why |
|--------|---------|-----|
| `feature-a` | **Yes** | Root of the stack, sits directly on `main`, no WIP commits → ready. |
| `feature-b` | No | Two reasons: (a) it is stacked on `feature-a` (not the root), and (b) its top commit `WIP: refactor helpers` is a WIP commit. |
| `feature-c` | No | Stacked on `feature-b` (not the root). |

Important: this is intentional, not a bug. `git-stack` publishes **one branch at a time from the bottom of the stack** so each GitHub PR stays scoped. Note that even if you reworded `feature-b`'s `WIP:` commit, it still would not push yet, because it is stacked above `feature-a` rather than sitting on `main`.

## The command plan (nothing here is run yet)

Run these in order:

```console
# 1. Sync first so you push a clean, current stack
$ git-stack sync

# 2. Dry-run: confirm exactly which branch(es) would push
$ git-stack --push -n        # expect: only feature-a marked (ready)

# 3. Publish the ready branch (force-push with lease, sets upstream)
$ git-stack --push

# 4. Open the PR for the bottom branch; base is the protected branch main
$ gh pr create --base main --head feature-a \
    --title "feat(user): add fetchUser" --body "<BLUF description>"
```

That publishes and opens a PR for `feature-a` only.

## Advancing the rest of the stack

Recommended (clean, scoped reviews): land one at a time.

1. When the `feature-a` PR merges, run `git-stack sync` — it rebases `feature-b` and `feature-c` onto the updated `main` and prunes the merged branch. `feature-b` then becomes the new root and turns ready (after you clear its WIP — see below).
2. `git-stack --push` again, then `gh pr create --base main --head feature-b ...`.
3. Repeat for `feature-c`.

To clear `feature-b`'s WIP so it can become ready, either finish the work or reword the commit (from the `git-stack-workflow` skill):

```console
$ git-stack reword <rev-of-WIP-commit> -m "refactor: extract helpers"
```

### If you want all three PRs open at once

You can publish them simultaneously, but then you must point each PR's base at the branch **below** it, not `main`:

```console
$ gh pr create --base main      --head feature-a --title "..." --body "..."
$ gh pr create --base feature-a --head feature-b --title "..." --body "..."
$ gh pr create --base feature-b --head feature-c --title "..." --body "..."
```

GitHub shows all commits on a branch (including ones "owned" by a lower PR), so this is noisier for reviewers; point them at the specific commits each PR owns. The one-at-a-time approach above avoids that. You would also still need to clear `feature-b`'s WIP and push the upper branches manually, since `git-stack --push` will not push them while they are stacked.

## Two caveats before you push

- **Remote config:** `git-stack --dump-config -` shows `push-remote=origin` / `pull-remote=origin`, but `git remote -v` lists no remotes and `main` shows `(no remote)`. The push and `gh` steps will fail until an `origin` remote exists. If you work from a fork, set `stack.pull-remote upstream` and `stack.push-remote origin`.
- **Per your conventions:** PR titles follow Conventional Commits and descriptions are BLUF — and nothing gets pushed until you explicitly ask. The commands above are a plan only.
