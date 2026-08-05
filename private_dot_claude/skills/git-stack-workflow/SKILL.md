---
name: git-stack-workflow
description: >-
  Drive the day-to-day stacked-branch authoring loop with the `git-stack` CLI:
  syncing against upstream, viewing the stack, navigating between commits/branches,
  editing earlier commits (amend/reword/fixup), running checks across the stack, and
  restacking branches onto new bases. Use this WHENEVER the user is working with
  stacked branches or stacked PRs, mentions `git-stack`/`git stack`/`git sync`/
  `git next`/`git prev`/`git amend`/`git reword`, asks to "rebase my stack",
  "sync my branches", "edit an earlier commit", "fix up a parent commit", "navigate
  the stack", or "run tests across the stack" — even if they don't name git-stack
  explicitly but the repo clearly uses a stacked-diff workflow. For pushing branches
  as PRs use `git-stack-publish`; for undoing/repairing a broken stack use
  `git-stack-recover`.
---

# git-stack daily workflow

`git-stack` automates the [stacked-diff](https://jg.gg/2018/09/29/stacked-diffs-versus-pull-requests/)
workflow on top of plain Git branches. Branches are the unit of work and review.
As you build branches on top of each other, `git-stack` handles the rebase
micromanagement that keeps the stack consistent.

This skill covers the authoring loop. It assumes the `git-stack` binary is
installed. The `git <cmd>` aliases (`git sync`, `git next`, …) are convenient but
often **not** registered, so this skill always invokes the binary directly as
`git-stack` / `git-stack <subcommand>`. That form works whether or not aliases
exist. (To set the short aliases up: `git-stack alias --register`.)

## Mental model — read this first

Everything `git-stack` does hinges on two branch categories:

- **Protected branches** — shared, upstream-controlled branches `git-stack` must
  never rewrite (e.g. `main`, `master`, `v3`). It rebases your work *onto* them
  but never edits their history. Check what's protected with
  `git-stack --protected -v`.
- **Development branches** — your local feature branches. `git-stack` freely
  rebases, reorders, and force-pushes these.

A **stack** is a chain of development branches/commits sitting on top of a
protected base. `git-stack` auto-detects the nearest protected base for each
branch, so you rarely specify it by hand.

`git-stack` defers all permanent changes (moving HEAD, retargeting branches)
until an operation fully succeeds, and snapshots branch state via
`git branch-stash` before rewriting history — so a failed or surprising
operation leaves you recoverable. When in doubt, prefer `--dry-run` / `-n`
first.

## The core loop

```console
$ git-stack sync                 # update protected branches + rebase your stack onto them
$ git switch -c feature1         # start a branch / PR
$ git add -A && git commit -m "Work"
$ git add -A && git commit -m "More work"
$ git-stack run cargo check      # verify each commit in the stack
$ git-stack                      # see the stack
```

Then iterate on earlier commits (next section), and when ready, hand off to the
**git-stack-publish** skill for `git-stack --push`.

## Viewing the stack

`git-stack` with no subcommand renders the stack on top of its protected base —
shorter and status-aware compared to `git log --graph`.

```console
$ git-stack                          # default view
$ git-stack --format graph           # branch graph (also: silent, list, debug)
$ git-stack --show-commits all       # none | unprotected | all
$ git-stack --stack all              # current | dependents | descendants | all
```

`--stack` selects which branches to include:
- `current` — branches in `BASE..HEAD` (default scope for most ops)
- `dependents` — `BASE..HEAD..` (your branch and everything stacked on it)
- `descendants` — `BASE..` (everything off the base)
- `all` — every branch

## Navigating the stack

To edit an earlier commit you first move HEAD to it. Don't hand-copy SHAs —
use navigation:

```console
$ git-stack previous          # move to the parent commit (alias: git prev)
$ git-stack next              # move to the child commit  (alias: git next)
$ git-stack previous 3        # jump back 3 commits
$ git-stack next -b           # jump to the next branch (not just commit)
$ git-stack previous --protected   # allow stepping onto protected commits
```

`--stash` stashes the working tree before switching; `--oldest` disambiguates
when a commit has multiple children.

## Editing history in the stack

The whole point of stacked diffs is freely revising earlier commits. After
`amend`/`reword`, `git-stack` automatically rebases all descendant commits and
branches onto the rewritten commit (unless that would conflict — see
`git-stack-recover`).

**Squash staged changes into a commit** — `git-stack amend`:
```console
$ git-stack previous                 # navigate to the commit to fix
$ git add -A
$ git-stack amend                    # meld staged changes into HEAD, keep message
$ git-stack amend -a                 # stage all changes + amend in one step
$ git-stack amend -e                 # also edit the message
$ git-stack amend <REV>              # amend a specific commit, not just HEAD
```

**Edit a commit message** — `git-stack reword`:
```console
$ git-stack reword                   # reword HEAD
$ git-stack reword -m "feat: better summary"
$ git-stack reword <REV>             # reword an ancestor; children get rebased
```

Prefer `reword`/`amend` over `git commit --amend` + manual rebase: they retarget
children for you and refuse to touch protected commits or commits referenced by
`fixup!` commits.

### The fixup workflow (fix an earlier commit without navigating)

If you spot a problem in an earlier commit while working at the top of the
stack, stage the fix and record a `fixup!` commit, then let `git-stack` move it
into place:

```console
$ git add -A
$ git commit --fixup <REV>           # records "fixup! <subject of REV>"
$ git-stack --rebase                 # applies stack.auto-fixup (move/squash/ignore)
$ git-stack --rebase --fixup squash  # force-squash fixups into their targets
$ git-stack --rebase --fixup move    # just reorder them next to their target
```

`--fixup` actions: `ignore` (leave them), `move` (reorder next to target),
`squash` (fold in). This overrides the `stack.auto-fixup` config for that run.

## Running checks across the stack

`git-stack run` walks each commit in the stack and runs a command, stopping at
the first failure — the fast way to confirm every commit still builds after you
rewrote history.

```console
$ git-stack run cargo test
$ git-stack run --no-fail-fast cargo check    # keep going past failures
$ git-stack run -s cargo test                 # on failure, switch to the broken commit
```

## Restacking onto a different base

`git-stack --rebase` moves development branches onto their relevant protected
base and runs "auto" operations (auto-fixup, optional auto-repair). To move a
stack somewhere specific, combine `--base` (what to move) and `--onto` (where):

```console
$ git-stack --rebase                                   # rebase stack onto latest protected base
$ git-stack --rebase --stack current --onto feature1   # stack current branch onto feature1
$ git-stack --rebase --base feature1 --onto main       # move whatever sits on feature1 over to main
```

Plain `git rebase` equivalents lose the inter-branch relationships; `git-stack`
preserves them. Always consider `--dry-run` on these structural moves first.

## sync vs. --rebase

- `git-stack sync` — pulls protected branches from `stack.pull-remote`, rebases
  your dev branches onto them, fetches `stack.push-remote` to prune deleted
  remotes, and deletes merged branches. No "auto" magic. Use it to catch merge
  and semantic conflicts early. **Run it at the start of a session and before
  pushing.**
- `git-stack --rebase` — local rebase onto the existing protected base plus auto
  operations (fixup, repair). Doesn't pull. Use it after recording fixups or to
  tidy the stack.

## Reference

For the full command/flag/config table — including every `stack.*` config field
(`stack.protected-branch`, `stack.auto-fixup`, `stack.push-remote`, …) — read
`references/commands.md` when you need a detail not covered above.

## Working tips

- This `git-stack` (v0.10.x) exposes navigation as `previous`/`next` and uses
  `--format` values `silent|list|graph|debug`. Older docs mention `prev` and
  other format names — trust `git-stack <cmd> --help` over stale docs.
- There is no `git-stack push`/`git-stack rebase` subcommand: pushing, rebasing,
  repairing, and fixup processing are **flags** on the top-level command
  (`git-stack --push`, `git-stack --rebase`, `git-stack --repair`).
- `git-stack` won't resolve conflicts — it stops and hands you back to `git
  rebase`. When that happens, switch to the **git-stack-recover** skill.
