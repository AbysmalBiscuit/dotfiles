---
name: rebase-latest-staging-push-rlsp
description: Rebase on Latest Staging and Push
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
---
Rebase on latest staging and push.

Takes an optional base branch argument; defaults to `staging`, else the remote HEAD.

## What already happened

`~/.agents/skills/rebase-latest-staging-push/scripts/rebase-latest-staging-push.sh` has **already run** — fetch, rebase, and push with
`--force-with-lease --force-if-includes`. Its output is below. Invoking `/rebase-latest-staging-push`
authorizes that force-push; it is the point of the command, not something to
second-guess or re-confirm.

The last line is `RLSP-RESULT: <STATUS>`. Everything you need about repo state is
in that output. Do not re-run `git status`, `git log`, `git branch -vv`, or
`git remote -v` to orient yourself or to double-check a result the script already
reported.

Formatting and linting are handled by the prek pre-push hook — don't run oxfmt or
oxlint by hand. If the rebase moved `bun.lock`, the script has already re-run
`bun install` — don't run it again.

---

!`bash ~/.agents/skills/rebase-latest-staging-push/scripts/rebase-latest-staging-push.sh "$ARGUMENTS" 2>&1 || true`

---

## Act on the status

| `RLSP-RESULT` | What to do |
|---|---|
| `PUSHED` | Done. Report the branch and its new tip in one line. Stop. |
| `UP-TO-DATE` | Done, nothing to push. Say so in one line. Stop. |
| `NO-COMMITS` | Done, branch has nothing of its own. Say so in one line. Stop. |
| `CONFLICT` | The real work — see below. |
| `INSTALL-FAILED` | `bun.lock` moved in the rebase and `bun install` failed. The rebase is committed; only the install failed. Read the install output, fix the cause, re-run the script. |
| `HOOK-MODIFIED` | The hook reformatted files. Amend them into the commit that owns them if it's unambiguous (single-commit branch, or the hunks belong to one commit), otherwise ask. Then re-run the script. |
| `DIRTY` | Uncommitted changes predate the command. Report what's uncommitted and ask whether to commit, stash, or drop. Don't decide for them. |
| `IN-PROGRESS` | A rebase was already running before this command. Report the state and ask how to proceed. |
| `REJECTED` | Someone else pushed to the branch. Do not override — show `git log HEAD..@{upstream}` and ask. |
| `PUSH-FAILED` | Read the hook/network/auth output above, fix the cause, re-run the script. |
| `PROTECTED` | You're on a protected branch. Report it and ask which branch they meant. |
| `ERROR` | Read the message, fix the precondition, re-run the script. |

## Resolving a `CONFLICT`

The rebase is **in progress** — the conflicted files are listed above and HEAD is
detached mid-replay. Resolve in place:

1. Read each conflicted file and the two sides (`git log -1 REBASE_HEAD` is the
   commit being replayed; the `HEAD` side is latest staging).
2. Resolve so **both** intents survive. If the two changes are genuinely
   incompatible and nothing in the repo, the commit messages, or the PR
   disambiguates, `git rebase --abort` and ask — don't silently pick a side.
3. `git add <files>` then `git rebase --continue`.
4. More conflicts may follow (the script reported how many commits are still
   queued). Repeat until the rebase finishes.
5. Re-run `bash ~/.agents/skills/rebase-latest-staging-push/scripts/rebase-latest-staging-push.sh` to push (pass the same base branch if
   one was given). It is safe to re-run at any point.
