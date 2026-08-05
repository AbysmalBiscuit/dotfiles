# Plan: sync your stack, then test every commit

Two commands, in order. Nothing below is run for you — this is the plan.

## 0. (Optional) See where you stand first — read-only

```bash
git-stack --dry-run            # preview what a rebase/sync would do, no changes
```

`--dry-run` (also available as `-n` on the subcommands) shows the intended
rebase without touching anything. Good sanity check before mutating history.

## 1. Update all stacked branches against upstream main

```bash
git-stack sync
```

`git-stack sync` ("Rebase local branches on top of pull remotes") fetches the
pull remote and rebases every local branch in your stack on top of the freshly
updated protected base branch (your `main`). This is the start-of-day "pull
upstream and restack everything" command.

- Dry-run it first if you want to preview: `git-stack sync --dry-run`
- If `sync` reports diverging branches after the rebase, repair them with
  `git-stack --repair`.
- If a rebase hits a conflict, git-stack stops and leaves you in a normal git
  rebase to resolve; fix conflicts, `git add`, `git rebase --continue`.

## 2. Confirm every commit in the stack still passes `cargo test`

```bash
git-stack run cargo test
```

`git-stack run` checks out each commit in the current stack in turn and runs the
given command against it, so you verify the whole stack compiles and tests
green commit-by-commit (not just the tip). Useful flags:

- `git-stack run --no-fail-fast cargo test` — don't stop at the first red
  commit; run the full stack and report every failure.
- `git-stack run --switch cargo test` — leave your working copy checked out on
  the first commit that failed, so you can jump straight in and fix it.

When it finishes you're back on your original commit (unless `--switch` parked
you on a failure).

## TL;DR

```bash
git-stack sync                 # 1. pull upstream main + restack all branches
git-stack run cargo test       # 2. run cargo test on every commit in the stack
```

If you registered the shell aliases (`git-stack alias --register`), these are
equivalently `git sync` and `git run cargo test`.

## Notes / unresolved

- `sync` rebases onto your most-recent **protected** branch. This assumes
  `main` is configured as protected (the default for the default branch). Check
  with `git-stack --protected` if unsure; add one with
  `git-stack --protect <branch>`.
- "Upstream main" here means whatever `sync` pulls from (your configured pull
  remote, e.g. `origin`/`upstream` for a fork). If you work from a fork and the
  upstream isn't your pull remote, confirm your push/pull-remote config before
  relying on `sync`.
