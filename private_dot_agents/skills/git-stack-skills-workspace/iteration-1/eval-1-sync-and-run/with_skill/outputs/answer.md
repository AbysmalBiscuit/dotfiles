# Start-of-day: sync the stack, then test every commit

Two `git-stack` commands do the real work — `sync` for goal (1), `run` for goal
(2). I've wrapped them with read-only checks and dry-runs so nothing is mutated
until you choose to run the live commands.

I invoke the binary directly as `git-stack` (not the `git sync` / `git next`
aliases), since those aliases are only registered if someone ran
`git-stack alias --register`. The binary form works either way.

## Plan

```console
# 0. Orient (read-only) — confirm what's protected and what the stack looks like
$ git-stack --protected -v          # verify `main` is the protected base you'll sync onto
$ git-stack                         # see the current stack before touching it

# 1. Update all stacked branches against latest upstream main
$ git-stack sync -n                 # DRY RUN: preview the pull + rebase, no changes
$ git-stack sync                    # pull protected branches from the pull-remote and
                                    #   rebase every dev branch in the stack onto them;
                                    #   also prunes/deletes merged branches

# 2. Confirm every commit in the current stack still passes the test suite
$ git-stack run -n cargo test       # DRY RUN: show which commits it would walk
$ git-stack run cargo test          # check out each commit in the stack in turn and
                                    #   run `cargo test`, stopping at the first failure

# 3. Confirm the result
$ git-stack                         # stack should now sit on the updated main
```

## Why these commands

- **`git-stack sync`** is the right tool for goal (1), not `git-stack --rebase`.
  `sync` actually *pulls* the protected branch from `stack.pull-remote` (your
  upstream `main`) and rebases the whole stack onto the fresh tip — exactly the
  "update against latest upstream main" you want at the start of the day.
  `--rebase` only rebases onto the *existing* local base and adds auto-fixup /
  auto-repair magic; it does not fetch upstream, so it would not pull in
  overnight changes. The skill's guidance: run `sync` at the start of a session.

- **`git-stack run cargo test`** is the tool for goal (2). It walks each commit
  in the current stack, checks it out, and runs the command, stopping at the
  first failure. That is what "every commit still passes `cargo test`" means —
  not just the tip. This matters especially after a `sync` rewrote history.

## Useful variations (optional)

- `git-stack run --no-fail-fast cargo test` — don't stop at the first broken
  commit; run the whole stack and collect every failure.
- `git-stack run -s cargo test` — on failure, leave you checked out **on** the
  first commit that failed, ready to fix it.
- Wider scope: by default `run` and `sync` operate on the current stack. If you
  have several independent stacks and want them all, add `--stack all`
  (e.g. `git-stack run --stack all cargo test`).

## If something goes sideways during the sync

`git-stack` does not resolve merge conflicts — if the rebase hits one it stops
and hands you back to plain `git`. In that case resolve and
`git rebase --continue`, or bail with `git rebase --abort` followed by
`git-branch-stash apply` to restore the pre-sync branch positions. (See the
git-stack-recover skill.) Nothing above is destructive beyond a normal rebase,
and `git-stack` snapshots branch positions via `git-branch-stash` before
rewriting history, so the sync is recoverable.

## Notes / caveats

- This assumes `stack.pull-remote` points at the upstream that holds `main`. On
  a fork it must be set to `upstream` (`git-stack --dump-config -` to check). If
  it is unset/wrong, `sync` would rebase onto a stale local `main`.
- The `-n` / dry-run lines are read-only previews. Drop them to actually run the
  sync and the tests.
- `cargo test` builds and runs the suite at *every* commit, so on a tall stack
  this can take a while; that is expected and is the price of verifying each
  commit independently.
