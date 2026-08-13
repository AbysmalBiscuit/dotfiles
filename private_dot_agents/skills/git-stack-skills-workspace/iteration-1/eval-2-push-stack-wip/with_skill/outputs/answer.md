# Pushing a three-branch stack with `git-stack` + `gh`

**Bottom line:** With your stack as described, a single `git-stack --push` will push **only `feature-a`**. `feature-b` and `feature-c` are deliberately held back — `feature-b` because it's both stacked on another dev branch *and* carries a `WIP:` commit, and `feature-c` because it's stacked. That's by design: `git-stack` publishes one PR at a time from the bottom of the stack. Plan below; nothing here is run for you.

## Why only `feature-a` is "ready"

`git-stack --push` force-pushes (with lease) only the development branches it considers **ready**. A branch is ready when **both** of these hold:

1. **It is not stacked on top of another development branch.** Only the root-of-stack branch — the one sitting directly on a protected base like `main` — is ready. Branches higher in the stack are held back.
2. **It has no WIP commits.** A commit is WIP if its summary is exactly `WIP` or starts with `WIP:`, `draft:`, `Draft:`, `wip `, or `WIP `.

(Note: `fixup!` commits do *not* block a push — only WIP and stacking do.)

Applying that to your stack:

| Branch | Sits on | WIP commit? | Ready? | Reason |
|--------|---------|-------------|--------|--------|
| `feature-a` | `main` (protected base) | no | **Yes** | Root of stack, no WIP |
| `feature-b` | `feature-a` (a dev branch) | yes — `WIP: refactor helpers` | No | Stacked on a dev branch **and** has a WIP commit (either alone is disqualifying) |
| `feature-c` | `feature-b` (a dev branch) | n/a | No | Stacked on a dev branch |

So even if you reworded the WIP commit on `feature-b`, it still wouldn't push in the same run — it's stacked on `feature-a`. `git-stack` intentionally advances the stack one merge at a time (see strategy below). The `WIP:` title is a second, independent reason `feature-b` is blocked, and a useful signal that it isn't ready for review.

## The command plan (review first — don't run blind)

```console
# 1. Sync so you publish a clean, current stack (updates main, rebases your branches onto it).
$ git-stack sync

# 2. See the stack and confirm the WIP marker on feature-b.
$ git-stack --show-commits all

# 3. DRY RUN the push — this shows which branches WOULD push WITHOUT pushing.
#    Expect: only feature-a.
$ git-stack --push -n

# 4. Do the real push (force-push-with-lease of ready branches to origin, sets upstream).
$ git-stack --push

# 5. Open the PR for the branch that was actually pushed (base = the protected branch).
$ gh pr create --base main --head feature-a \
    --title "feat(...): <summary of feature-a>" \
    --body "<BLUF description; link the issue>"
```

Your remote config here is already single-remote (`origin` for both pull and push), and protected branches include `main`/`master`/`dev`/`stable`, so no fork setup is needed. Verify any time with `git-stack --dump-config -`.

## What actually gets pushed, and why

- **`git-stack sync`** pulls `main` from `origin`, rebases `feature-a → feature-b → feature-c` onto it, prunes deleted remotes, and deletes already-merged branches. No history "magic" — it just surfaces conflicts early. Run it before pushing.
- **`git-stack --push -n`** is the safety check: it lists the ready set without mutating anything. With your stack it should report `feature-a` only. If it shows nothing, re-check that `feature-a` really sits directly on `main`.
- **`git-stack --push`** then force-pushes (with lease) `feature-a` to `origin` and sets its upstream. `feature-b` and `feature-c` are skipped so you don't publish half-baked (`WIP`) or dependent work.
- **`gh pr create --base main --head feature-a`** opens the one PR whose base is the protected branch.

## Advancing the rest of the stack (later)

Because only the bottom branch is ready, you advance one merge at a time:

1. Get `feature-a`'s PR reviewed and merged.
2. Reword the WIP commit on `feature-b` once it's real work: `git-stack reword <REV> -m "refactor: <summary>"` (or finish the work). While it's titled `WIP:`, it will never push.
3. `git-stack sync` — this rebases `feature-b` (and `feature-c`) onto the updated `main`. Now `feature-b` sits directly on the protected base and, with no WIP commit, becomes **ready**.
4. `git-stack --push -n` then `git-stack --push` to publish `feature-b`; open its PR with `gh pr create --base main --head feature-b`.
5. Repeat for `feature-c`.

### If you must publish all three PRs at once

You can, but the base of each stacked PR is the **branch below it**, not `main`, and GitHub will show every commit on the branch (noisy):

```console
$ gh pr create --base main      --head feature-a --title "..." --body "..."
$ gh pr create --base feature-a --head feature-b --title "..." --body "..."
$ gh pr create --base feature-b --head feature-c --title "..." --body "..."
```

`git-stack --push` still won't push `feature-b`/`feature-c` for you while they're stacked (and `feature-b` while it's WIP), so you'd push those branches manually — the recommended path is the one-at-a-time flow above.

## Reminders

- Per your conventions: **nothing is pushed and no PR is opened until you run the commands yourself.** This is a plan only.
- PR titles follow Conventional Commits; descriptions are BLUF and link the issue.
- If a push rewrites something you didn't intend, `git-stack` snapshots branch positions first — `git-branch-stash list` / `apply` can undo it (see the recover skill).

## Unresolved questions

1. Is `feature-b`'s `WIP: refactor helpers` commit actually finished work that just needs a reword, or genuinely incomplete? That decides whether step 2 above is a one-line reword or real coding.
2. Do you want all three PRs visible now (stacked-base approach), or the cleaner one-PR-at-a-time flow as `feature-a` merges?
3. Are you working in the upstream repo directly (current config: `origin` for both pull and push), or did you intend to push to a fork? If a fork, set `stack.push-remote`/`stack.pull-remote` before pushing.
