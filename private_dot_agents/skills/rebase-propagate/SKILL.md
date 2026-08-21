---
name: rebase-propagate-rp
description: Rebase on latest staging and propagate down the stack of dependent PRs
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
---
Rebase this branch on latest staging and propagate the result to every dependent PR.

Takes an optional base branch argument; defaults to `staging`, else the remote HEAD.

## What already happened

`~/.agents/skills/rebase-propagate/scripts/rebase-propagate.sh` has **already run**. It fetched, discovered
the stack from GitHub (every open PR whose base is a branch in the stack, recursively),
rebased each branch onto its new parent, pushed them all with
`--force-with-lease --force-if-includes`, and scanned for duplicate PRs. Its output is
below. Invoking `/rebase-propagate` authorizes those force-pushes.

Nothing is pushed until every rebase succeeds, so a `CONFLICT` means the remote is
untouched and the run is resumable.

The last line is `RP-RESULT: <STATUS>`; a `RP-DUPES: <n>` line precedes it when the
dupe scan ran. Everything you need about repo and PR state is in that output. Do not
re-run `git status`, `git log`, `gh pr list`, or `gh pr view` to orient yourself or to
double-check a result the script already reported.

---

!`bash ~/.agents/skills/rebase-propagate/scripts/rebase-propagate.sh "$ARGUMENTS" 2>&1 || true`

---

## Act on the status

| `RP-RESULT` | What to do |
|---|---|
| `PROPAGATED` | The rebase work is done. Handle dupes per the section below, then report the stack in one short table. Stop. |
| `NOTHING-TO-DO` | Already current. Say so in one line, handle dupes, stop. |
| `CONFLICT` | The real work — see below. |
| `DIRTY` | Uncommitted changes predate the command. Report them and ask whether to commit, stash, or drop. Don't decide for them. |
| `IN-PROGRESS` | A rebase was already running before this command. Report the state and ask how to proceed. |
| `REJECTED` | Someone else pushed to a branch in the stack. Do not override — show `git log <branch>..origin/<branch>` and ask. |
| `HOOK-MODIFIED` | The prek pre-push hook reformatted files. Amend them into the commit that owns them if unambiguous, otherwise ask. Then re-run the script. |
| `PUSH-FAILED` | Read the hook/network/auth output above, fix the cause, re-run the script. Note which branches already pushed. |
| `PROTECTED` | You're on a protected branch. Report it and ask which branch they meant. |
| `ERROR` | Read the message, fix the precondition, re-run the script. |

If the output contains the `gh could not resolve a GitHub repo` note, say so plainly —
only the current branch was handled and dependent PRs were **not** propagated.

## Resolving a `CONFLICT`

The rebase is **in progress** on the branch named in the output, and nothing has been
pushed. The remaining branches are queued behind it.

1. Read each conflicted file and the two sides (`git log -1 REBASE_HEAD` is the commit
   being replayed).
2. Resolve so **both** intents survive. If the two changes are genuinely incompatible
   and nothing in the repo, the commit messages, or the PRs disambiguates, ask —
   don't silently pick a side.
3. `git add <files>` then `git rebase --continue`, repeating for further conflicts on
   that branch.
4. Re-run `bash ~/.agents/skills/rebase-propagate/scripts/rebase-propagate.sh`. It resumes the same run from
   its state file — including the branches already rebased — and pushes the whole
   stack once every rebase lands. Do **not** push by hand: a partial push is exactly
   the inconsistent state this avoids.
5. Later branches may conflict too. Repeat until `RP-RESULT: PROPAGATED`.

## Duplicate PRs

The scan lists each extra open PR sharing a head branch with one in the stack:

- `CLEAR-DUPE` — same head, same base, same title, bot-authored. Close it:
  `gh pr close <n> --comment "duplicate of #<keep>"`. Batch them into one command.
- `AMBIGUOUS` — differs in base, title, or author. Do **not** close it. Report it and
  ask.

`RP-DUPES: 0` means nothing to do — don't verify it further.

The retired auto-pr workflow could in principle open a dupe shortly after the push.
The scan above already ran post-push. If you want the delayed re-check, run
`bash ~/.agents/skills/rebase-propagate/scripts/rebase-propagate.sh --dupes` once — it is read-only. Never
`sleep` to wait for it.
