---
name: issue-review-ir
description: Ship the current issue worktree — push, open/reuse the PR, and request a reviewer only if one is named
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskUpdate, TaskList, TaskGet
argument-hint: "[reviewer-alias] (optional — omit to request nobody)"
---
# /issue-review

Ship a finished (or just-updated) issue worktree: commit, push, open **or** reuse the
PR with the Linear id stamped on by the devkit templates.

**A reviewer is requested only when an alias is passed.** With no argument, nobody is
added on GitHub and nobody is notified — the PR just gets opened or updated.

## What already happened

`~/.claude/scripts/issue-review-recon.sh` has **already run**, read-only. It resolved
the reviewer alias if one was given, detected the PR state, picked the branch of the
workflow that applies, and gathered the diff you need. Its output is below.

It ends with `IR-BRANCH: A | B | STOP` and `IR-RESULT: <STATUS>`. Everything you need
about worktree, PR, and diff state is in that output. Do not re-run `issue info`,
`gh pr view`, `git status`, `git log`, or `git diff` to orient yourself.

It deliberately did **not** commit, push, or open the PR — those need prose only you
can write. That is the work left for you.

---

!`bash ~/.claude/scripts/issue-review-recon.sh "$ARGUMENTS" 2>&1 || true`

---

## Act on the result

| `IR-RESULT` | What to do |
|---|---|
| `READY` + `IR-BRANCH: A` | No PR yet — Branch A below. |
| `READY` + `IR-BRANCH: B` | PR open — Branch B below. |
| `NOTHING-NEW` | Tell the user there's nothing new to ship. Stop. |
| `PR-MERGED` / `PR-CLOSED` | Report it; there's nothing to do. Stop. |
| `PROTECTED` | Report the branch and ask which worktree they meant. Stop. |
| `NOT-ISSUE-WORKTREE` | Report it. Ask whether to run from an issue worktree or supply title/body without the templates. Stop. |
| `UNKNOWN-REVIEWER` | An alias *was* passed and isn't in the devkit config. Report it and the known ones, and ask. Stop. |
| `ERROR` | Read the message, fix the precondition, re-run the script. |

On `READY`, open the four steps of the branch named in `IR-BRANCH` as tasks —
`TaskCreate` one per step, `TaskUpdate` each to `in_progress` as you start it and
`completed` as it lands — then work them. If those tools are unavailable, keep the
four steps as a list in your replies; do not go looking for a tracking tool.

On any other result there is nothing to track — report and stop.

Stop and ask if any step below fails or is ambiguous — never force-push, never invent
a summary the diff doesn't support.

### Branch A — no PR yet

1. **Judge the work.** The diff is above. Confirm the change is actually complete and
   coherent before shipping it. Untracked files are listed separately — decide
   whether each belongs in the commit.
2. **Commit** anything pending with a conventional-commit message derived from the
   issue + diff. Nothing below commits for you.
3. **Draft the PR title + body** with the **`/write` skill**. Leave the Linear id out
   of both, and don't open the body with a heading — read *Linear ids and magic words*
   below before drafting.
4. **Ship it** with the `issue review request` printed under `== next ==`, filling in
   the placeholders. With no alias it runs `--no-notify` instead of `--to`, with no
   trailing positional — the PR opens unreviewed and nothing is delivered. Decide the
   magic word first (same section).

### Branch B — PR already open

1. **Judge the work.** The diff above is scoped to what the reviewer has *not* seen
   (since the last submitted review, or since the pushed tip if none exists yet).
2. **Commit** anything pending with a conventional-commit message describing the
   changes.
3. **Summarize** what landed — a tight 1–2 sentences backed by that diff. With an alias
   this is the ask that goes out with the review request; with none it is just what you
   report back.
4. **Ship it** with the `issue review request` printed under `== next ==`. No
   `--pr-title`/`--pr-body` either way — the PR body was fixed at creation.

With no alias the command carries `--no-notify`, which leaves the PR's existing
reviewers exactly as they are: nobody is added, re-requested, or delivered to. Without
that flag a missing `--to` on an *existing* PR falls back to its current human
reviewers and pings them, so never drop it to "just push".

## Linear ids and magic words

The PR is the only thing that links this work to Linear. Linear reads magic words in
the **PR title and description only** — never in commit messages or PR comments — and
the word must sit directly before the id with nothing running into it.

`issue review request` renders both from the worktree's issue record, so you write
neither by hand — that holds with or without a reviewer.

**Title.** `pr_title` appends ` [<ISSUE>]` to your title unless the id is already in
it. Write a plain conventional-commit subject with no id — the suffix costs title
budget the template accounts for, and adding the id yourself just suppresses the
bracket convention.

**Body.** `pr_body` renders:

```
## TL;DR (human written)

<!-- Lev fill this in -->

## Linear

Closes ADA-123

<your body text>
```

Two consequences for what you draft:

- Your text lands at the **bottom**, after the Linear section. Don't open it with a
  `## TL;DR` heading — the template already emits one, and that placeholder is Lev's to
  fill, not yours.
- Don't write `Closes ADA-123` yourself. The template drops its entire `## Linear`
  section when `<magic word> <issue>` already appears in your text, so you'd trade a
  structured section for a bare line at the bottom.

**Choosing the magic word.** `Closes` is the default and transitions the issue to done
on merge. If this PR must **not** close the issue (partial work, one of several PRs),
add `--arg linear_magic_word=Ref` — it still links, but merging won't transition. Other
contributing words: `references`, `part of`, `related to`, `contributes to`, `towards`.
Ask the user if it's unclear whether the PR closes the issue.

**More than one issue.** `--arg also_closes="ADA-124 ADA-125"` adds a line per extra id
under the same magic word. Empty by default, so it costs nothing when unused. A PR that
closes one issue but only references another can't be expressed this way — every id in
the list gets the same word, so add the odd one out to the description by hand.

`--arg` only accepts keys declared under `[templates.variables]` — `linear_magic_word`
and `also_closes` — so a mistyped key is rejected rather than silently ignored.

**There is no second chance.** `pr_title` / `pr_body` render only when the PR is
created; on an existing PR `issue review request` ignores `--pr-title` / `--pr-body`.
To change the magic word or add an id afterwards, edit the description with
`gh pr edit`.

## Notes

- The subcommand is `issue review request`, not `issue review` — the latter is a
  command group and exits non-zero.
- `--no-notify` pins the notify targets to whatever `--to` gave, so it never falls back
  to a PR's current reviewers. With no `--to` that is nobody: it pushes, opens or reuses
  the PR, prints the URL, and stops. Combined with `--to` it still adds the GitHub
  reviewer while staying off Slack.
- Opening a PR with no `--to` is allowed because `defaults.require_pr_reviewer` is off,
  and `--no-notify` does not bypass that gate. If it is ever turned on, creating a PR
  needs a real `--to` — and the push happens *before* that check. Passing `--to ""` is
  never a workaround; the empty alias fails to resolve, also after the push.
- Never force-push. Both paths run a plain `git push -u`; if the branch has diverged it
  fails — surface the error and ask, don't retry blindly.
- Override the GitHub handle or base only when needed: `--reviewer <gh-handle>`,
  `--base <branch>`. Skip the push with `--no-push`.
- The trailing positional on `issue review request` is the one-line ask sent with the
  request. The `review_request` template appends the PR URL, so don't paste the link
  into it. Keep it short and in the user's voice — no AI throat-clearing.
- Mentioning the issue id in a commit message is decorative. Linear ignores it there, so
  never reword a commit to carry a magic word.
- If the shipping command fails, show the exact error and stop.
