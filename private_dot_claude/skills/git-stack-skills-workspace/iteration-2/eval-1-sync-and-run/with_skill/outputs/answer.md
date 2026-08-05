# Start-of-day: sync the stack, then verify every commit

Two steps, in order. Nothing here is run for you — this is the plan.

## 1. Update all stacked branches against the latest upstream main

```console
$ git-stack sync
```

`git-stack sync` is the start-of-session command: it pulls the protected
branches (`main`/`master`) from `stack.pull-remote`, rebases every one of your
development branches onto the freshly updated base, fetches `stack.push-remote`
to prune deleted remotes, and deletes merged dev branches. It does **not** run
any "auto" magic (no auto-fixup/auto-repair) — which is exactly what you want at
the start of the day, so merge and semantic conflicts surface early.

Tips:
- Preview first if you want to see what it'll touch: `git-stack sync -n`
  (`--dry-run`).
- After it finishes, look at the result: `git-stack` (or `git-stack --format
  graph` for the fuller picture).
- If `sync` stops on a merge conflict, `git-stack` hands control back to plain
  Git — resolve with `git add` + `git rebase --continue` (or
  `git rebase --abort` to bail). That's the **git-stack-recover** territory; it
  won't resolve conflicts for you.

Note: use `sync`, not `git-stack --rebase`. `--rebase` only does a *local*
rebase onto the existing base (plus auto-fixup/repair) and does **not** pull
upstream — so it wouldn't pick up "the latest upstream main."

## 2. Confirm every commit in the stack still passes `cargo test`

```console
$ git-stack run cargo test
```

`git-stack run` walks each commit in the current stack, checks it out, and runs
the command — stopping at the first commit that fails. That's how you confirm
the whole rebased stack is green, commit by commit (not just the tip).

Useful variants:
- `git-stack run --no-fail-fast cargo test` — don't stop at the first failure;
  test every commit and report all the broken ones.
- `git-stack run -s cargo test` — on failure, leave you switched to the first
  broken commit so you can fix it immediately (then `git-stack amend`).

By default `run` operates on the `current` stack scope. If you want to verify a
wider set of branches, add a scope, e.g.
`git-stack run --stack dependents cargo test`.

## The whole plan, condensed

```console
$ git-stack sync                 # 1. pull upstream + rebase all stacked branches
$ git-stack                      # (optional) eyeball the synced stack
$ git-stack run cargo test       # 2. run cargo test at every commit, fail-fast
```

Everything here invokes the `git-stack` binary directly, so it works whether or
not the short `git sync` / `git run` aliases were registered.
