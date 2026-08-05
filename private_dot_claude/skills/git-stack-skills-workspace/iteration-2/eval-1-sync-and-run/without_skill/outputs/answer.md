# Start-of-day plan: sync the stack, then run `cargo test` across every commit

Two steps. Step 1 rebases all your stacked branches onto fresh upstream `main`; step 2 walks every commit in the current stack and runs `cargo test` against each one. Don't execute until you've eyeballed the dry runs.

## Step 0 (optional but recommended): preview the sync

```sh
git-stack --dry-run
```

`git-stack` with no subcommand shows the current state of your stacks. Adding `--dry-run` (and optionally `--format graph`) lets you see what would change before anything is rewritten:

```sh
git-stack --pull --dry-run --format graph
```

## Step 1: update all stacked branches against latest upstream main

```sh
git-stack sync
```

`git-stack sync` fetches the pull remote and rebases your local branches on top of it — this is the start-of-day "get on top of upstream main" command. It pulls the protected base branch (e.g. `main`) and restacks your branches onto the new tip.

Notes:
- Run `git-stack sync --dry-run` first if you want to see the planned rebases without touching anything.
- `sync` operates across your stacks, so all stacked branches get moved onto the updated base in one shot.
- If a rebase hits a conflict, git-stack stops; resolve the conflict, then re-run to continue. (Equivalent lower-level form: `git-stack --pull --rebase`.)

After syncing, confirm the new shape:

```sh
git-stack --format graph
```

## Step 2: run `cargo test` on every commit in the current stack

```sh
git-stack run cargo test
```

`git-stack run <command> <args...>` checks out each commit in the current stack in turn and runs the command, reporting pass/fail per commit. This is exactly the "does every commit still build/test" check.

Useful flags:
- `git-stack run --no-fail-fast cargo test` — keep going and test *all* commits even after one fails, so you get the full picture instead of stopping at the first red commit.
- `git-stack run --switch cargo test` — on failure, leave you checked out on the first commit that failed, ready to fix it (pair with `git-stack amend` / `git-stack reword` to repair, then re-run).
- `git-stack run --dry-run cargo test` — show which commits it would visit without running anything.

Recommended first pass:

```sh
git-stack run --no-fail-fast cargo test
```

so you see every failing commit in one run, then drill in with `--switch` to fix.

## TL;DR

```sh
git-stack sync                              # 1. rebase whole stack onto latest upstream main
git-stack run --no-fail-fast cargo test     # 2. cargo test every commit in the current stack
```

(Prefix either with `--dry-run` first if you want a no-op preview. `run` returns to your original commit when done.)
