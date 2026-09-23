---
name: rebase-latest-force-push-rlfp
description: Rebase on the Latest Base Branch and Force-Push [rlfp]
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
---

Rebase the current branch on the latest base branch and force-push it.

Takes an optional base branch argument. Without one, the base resolves in order: `git config base.branch`, then `staging`, then the remote's default branch.

## Run the script

When the user invokes this workflow, run the following command with the shell tool's working directory set to the target repository. Invoking the workflow authorizes its fetch, rebase, and push with `--force-with-lease --force-if-includes`. Reading or editing this skill alone does not invoke the workflow.

```bash
python3 /home/lev/.agents/skills/rebase-latest-force-push/scripts/rebase_latest_force_push.py
```

If the user supplied a base branch, append it as one shell-quoted argument. Read it from the invocation or user request; `$ARGUMENTS` is not a shell variable to rely on. Keep the same repository and base argument for retries.

Wait for the command to finish and read both stdout and stderr, including on a nonzero exit. The last line is `RLFP-RESULT: <STATUS>`; use the table below to choose the next action. If no result marker appears, diagnose the execution failure before retrying. A command shown in this document is an instruction to execute, not evidence that it ran.

Use the script's output to orient yourself. Run additional Git queries only when needed to resolve a reported failure or ambiguity.

Formatting and linting are handled by the prek pre-push hook. Use its results instead of running oxfmt or oxlint separately. If the script reports a successful lockfile install, reuse that result; if it reports a failure or skipped install, address the reported cause.

## Act on the status

| `RLFP-RESULT` | What to do |
|---|---|
| `PUSHED` | Done. Report the branch and its new tip in one line. Stop. |
| `UP-TO-DATE` | Done, nothing to push. Say so in one line. Stop. |
| `NO-COMMITS` | Done, branch has nothing of its own. Say so in one line. Stop. |
| `CONFLICT` | The real work — see below. |
| `STACKED` | The branch sits on unmerged branches that are still on the remote, so nothing was rebased. Report the parents the script listed and ask which they want: `/rebase-propagate` for the whole stack, or re-running this with the parent as the argument. Don't pick for them. |
| `INSTALL-FAILED` | A lockfile moved in the rebase and its install failed. The rebase is committed; only the install failed. The header line names the command that ran. Read the install output, fix the cause, re-run the script. |
| `HOOK-MODIFIED` | The hook reformatted files. Amend them into the commit that owns them if it's unambiguous (single-commit branch, or the hunks belong to one commit), otherwise ask. Then re-run the script. |
| `DIRTY` | Uncommitted changes predate the command. Report what's uncommitted and ask whether to commit, stash, or drop. Don't decide for them. |
| `IN-PROGRESS` | A rebase was already running before this command. Report the state and ask how to proceed. |
| `REJECTED` | Someone else pushed to the branch. Do not override — show `git log HEAD..@{upstream}` and ask. |
| `PUSH-FAILED` | Read the hook/network/auth output above, fix the cause, re-run the script. |
| `PROTECTED` | You're on a protected branch. Report it and ask which branch they meant. |
| `ERROR` | Read the message, fix the precondition, re-run the script. |

## Resolving a `CONFLICT`

The rebase is **in progress**. The script lists the conflicted files and HEAD is detached mid-replay. Resolve in place:

1. Read each conflicted file and the two sides (`git log -1 REBASE_HEAD` is the commit being replayed; `HEAD` contains the base plus any commits already replayed).
2. Resolve so **both** intents survive. If the two changes are incompatible and nothing in the repo, the commit messages, or the PR disambiguates, `git rebase --abort` and ask.
3. `git add <files>` then `git rebase --continue`.
4. More conflicts may follow (the script reported how many commits are still queued). Repeat until the rebase finishes.
5. Once the rebase finishes, run the script again in the same repository with the same base argument to push. Read the new `RLFP-RESULT` and act on it.
