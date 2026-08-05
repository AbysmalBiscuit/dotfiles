# Pushing your stack and opening PRs

Short version: if you run `git-stack --push` right now, **only `feature-a` gets pushed.** `feature-b` is held back because its top commit is titled `WIP: refactor helpers`, and `feature-c` is held back because it sits on top of a branch that isn't ready. You'll need to clear the `WIP:` marker first if you want all three pushed.

## Why the WIP commit blocks the push

`git-stack` decides which branches are "ready" to push. A branch is **not** ready if any of its commits is a work-in-progress commit, and `git-stack` treats a commit whose summary starts with `WIP` (and also `fixup!` / `squash!` commits) as work-in-progress. The rule is conservative on purpose: you don't accidentally publish half-finished work.

Two consequences for your stack:

1. `feature-b`'s tip commit `WIP: refactor helpers` marks `feature-b` as not ready, so `git-stack` skips it.
2. Because a stack must be pushed in order (a child branch's base on the remote has to exist), once `feature-b` is skipped, `feature-c` (stacked on top of it) is skipped too — even though `feature-c` itself has no WIP commit.

So the protected base branch (`main`) is never pushed, `feature-a` is pushed, and the WIP on `feature-b` stops `feature-b` and everything above it.

## Step 1 — Look before you leap (no mutations)

```bash
# Show the stack and how git-stack sees each branch
git-stack

# Dry-run the push: prints exactly what WOULD be pushed, changes nothing
git-stack --push --dry-run
```

The dry run is the authoritative answer to "what will actually get pushed" — expect to see only `feature-a` listed, with `feature-b`/`feature-c` reported as held back / not ready (WIP).

It's also worth confirming where it would push:

```bash
# Which remote git-stack pushes to (origin by default; a fork if configured)
git config stack.push-remote
git config stack.pull-remote
git remote -v
```

If `stack.push-remote` is unset, `git-stack` pushes to your normal `origin`. If you work from a fork, set `push-remote` to the fork and `pull-remote` to upstream.

## Step 2 — Decide what you actually want to publish

**Option A: You want all three branches up now.** Clear the WIP marker on `feature-b`'s tip so the branch becomes ready. You don't have to finish the work — just retitle the commit so it's no longer a `WIP:` commit:

```bash
# Navigate to feature-b's tip, then reword it to drop the "WIP:" prefix
# e.g. "WIP: refactor helpers" -> "refactor helpers"
git-stack reword          # rewords the current commit
# (or check out feature-b and: git commit --amend  to edit the message)
```

After rewording, re-run the dry run — all three branches should now show as ready:

```bash
git-stack --push --dry-run
```

**Option B: `feature-b` really is unfinished.** Then leave the WIP as-is and only `feature-a` will go up. That's the correct, intended behavior — publish `feature-a` now, finish `feature-b` later, and push again. Don't force the WIP commit out the door if it isn't ready.

## Step 3 — Push (when you're ready; you said don't push yet)

```bash
git-stack --push
```

This force-pushes (with lease) each ready branch to the push remote under its own name. With the WIP cleared you'll get `feature-a`, `feature-b`, `feature-c`; with the WIP left in place you'll get only `feature-a`.

## Step 4 — Open the PRs with `gh`, base-by-base

`git-stack` pushes branches; it does **not** create GitHub PRs. You open those yourself with `gh`, and the key is that each PR targets the branch **below** it, not `main` — otherwise GitHub shows every commit in the stack in every PR.

Open them bottom-up, one per branch:

```bash
# feature-a is the bottom of the stack -> targets the trunk
gh pr create --base main      --head feature-a --title "feature-a" --body "..."

# feature-b stacks on feature-a
gh pr create --base feature-a --head feature-b --title "feature-b" --body "..."

# feature-c stacks on feature-b
gh pr create --base feature-b --head feature-c --title "feature-c" --body "..."
```

Only run the `gh pr create` line for branches that were actually pushed. If you kept the WIP on `feature-b`, you can only open the `feature-a` PR for now; open the other two after you clear the WIP and push again. (Tip: add `--draft` to any PR you want to mark not-ready-for-review on GitHub.)

### One caveat about stacked bases on GitHub

Each PR's diff is correct as long as its base branch exists on the remote and points where you expect. When `feature-a` later merges into `main`, retarget `feature-b`'s PR to `main` (`gh pr edit feature-b --base main`) — or just let `git-stack` restack and re-push, then update the base. GitHub also auto-retargets a stacked PR to the trunk when its base branch is merged.

## TL;DR

- Run `git-stack --push --dry-run` first — it will show only `feature-a` as pushable.
- `feature-b` is blocked by its `WIP: refactor helpers` tip commit; `feature-c` is blocked because it's stacked above a not-ready branch.
- To push all three, reword `feature-b`'s tip to drop the `WIP:` prefix, then `git-stack --push`.
- `git-stack` pushes branches; you open PRs with `gh pr create`, each `--base` pointing at the branch directly beneath it (`feature-a`→`main`, `feature-b`→`feature-a`, `feature-c`→`feature-b`).
