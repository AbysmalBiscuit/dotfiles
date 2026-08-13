---
name: git-stack-publish
description: >-
  Push stacked development branches to a remote and open them as PRs using
  `git-stack --push` together with the `gh` CLI. Covers which branches `git-stack`
  considers "ready", the WIP/fixup rules that hold a branch back, push-remote vs.
  pull-remote (fork) configuration, and the practical strategy for stacking PRs on
  GitHub (one PR at a time, correct base branches). Use this WHENEVER the user wants
  to "push my stack", "push ready branches", "publish/open stacked PRs", "force-push
  my branches", set up a fork's push/pull remotes, or asks why a branch in a stack
  isn't being pushed. For editing/rebasing the stack first use `git-stack-workflow`;
  for undoing a bad push or repairing the stack use `git-stack-recover`.
---

# Publishing a stack as PRs

Once the stack is clean (synced and rebased — see **git-stack-workflow**),
`git-stack --push` publishes the branches that are ready, and `gh` opens the PRs.

This skill invokes the binary directly (`git-stack --push`); the `git stack
--push` alias is equivalent only if `git-stack alias --register` was run.

## Push the ready branches

```console
$ git-stack sync                 # always sync first so you push a clean, current stack
$ git-stack --push -n            # dry-run: see which branches WOULD push
$ git-stack --push               # force-push ready branches to stack.push-remote
```

`--push` force-pushes (with lease) the *ready* development branches to
`stack.push-remote` and sets their upstream. It deliberately skips branches that
aren't ready, so you don't publish half-baked or dependent work.

## What "ready" means

A development branch is **ready** to push when both hold:

1. **It is not stacked on top of another development branch.** Only the
   root-of-stack branch (the one sitting directly on a protected base) is ready.
   Branches stacked higher are held back — see the GitHub strategy below for why.
2. **It has no WIP commits.**

Branches that contain `fixup!` commits are still considered ready (so reviewers
can see intermediate states). If you don't want `fixup!` commits merged, gate
them with a tool like [`committed`](https://github.com/crate-ci/committed) rather
than blocking the push.

### When is a commit "WIP"?

A commit counts as WIP if its summary is exactly `WIP` or starts with any of:
`WIP:`, `draft:`, `Draft:`, `wip `, `WIP `. (These match the GitLab draft
prefixes.) To make a branch pushable, reword the WIP commit
(`git-stack reword`) or finish the work.

**If a branch isn't pushing, check these first:** run `git-stack --push -n` and
`git-stack --show-commits all` to see WIP markers, and confirm the branch isn't
stacked on another dev branch.

## push-remote vs. pull-remote (forks)

`git-stack` separates the remote you pull shared branches from and the remote you
push your work to:

- **`stack.pull-remote`** — upstream, holds shared protected branches. Never
  rewritten locally.
- **`stack.push-remote`** — where your personal branches go; `git-stack` assumes
  it owns these and may force-push them.

Working directly in the upstream org, these are the same (usually `origin`).
Working from a fork:

```console
$ git config --add stack.pull-remote upstream     # shared branches live here
$ git config --add stack.push-remote origin        # your fork
```

Verify with `git-stack --dump-config -`.

## Opening the PRs on GitHub

Use the `gh` CLI (the user's preferred GitHub tool). Per the user's conventions:
**don't open or push a PR unless asked**, PR titles follow Conventional Commits,
and descriptions are BLUF.

```console
$ git-stack --push                                   # publish ready branch(es)
$ gh pr create --base main --head feature1 \
    --title "feat(x): summary" --body "..."          # base = the protected branch
```

For a branch stacked on another, the PR's base is the **branch below it**, not
`main`:

```console
$ gh pr create --base feature1 --head feature2 --title "..." --body "..."
```

## Strategy: stacking PRs on GitHub

GitHub shows *all* commits on a branch, even ones "owned" by a lower PR, so a
naive stack of PRs is noisy. Recommended approach:

- **Post one PR at a time within a stack** — typically the bottom branch. This is
  exactly why `git-stack --push` only treats the root branch as ready.
- When the bottom PR merges, run `git-stack sync` to rebase the rest onto the
  updated protected base, then the next branch becomes ready to push.
- If you must publish several at once, retarget each PR's base to the branch
  below it (as above) and point reviewers at the specific commits each PR owns.
  Each PR will still show the CI status of its top commit.

This keeps review scoped and lets the stack advance one merge at a time.

## After publishing

- Re-pushing after edits: just rebase/amend in **git-stack-workflow**, then
  `git-stack --push` again — it force-pushes with lease.
- Pushed the wrong thing or need to undo a rewrite: see **git-stack-recover**
  (`git branch-stash`).
