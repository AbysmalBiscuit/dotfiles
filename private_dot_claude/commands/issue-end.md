---
description: Find finished issue worktrees (PR merged + Linear done), triage their artifacts, then remove worktree + ISSUE_*.md files
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__linear__get_issue
---

# /issue-end

Clean up issue worktrees whose work is finished, using **`issue end`** (the devkit
binary) for the scan, the finished-gate, and the removal. A worktree is **finished**
only when its GitHub PR is merged **and** its Linear issue is Done **and** the tree is
clean — `issue` computes that verdict for you, so there's no separate scan script or
manual Linear check. Your one added job is rescuing each finished worktree's artifacts
**before** removal, since `issue end` deletes the worktree wholesale.

Worktrees live under the configured `worktree_root` (`~/Git/adaptyv`), siblings of the
`monorepo` clone, with handoff files `ISSUE_SUMMARY_<ID>.md` in that parent dir. Created
by `/issue-setup`.

## Input

`$ARGUMENTS` = optional issue ID(s) to limit the cleanup to (e.g. `ENG-1234 DBI-986`).
Empty = consider all worktrees of the repo containing the current dir.

## Steps

### 1. Scan + verdict (read-only)

```bash
issue status $ARGUMENTS
```

This prints every worktree with its PR state, Linear state, tree cleanliness, and a
**VERDICT** column (`FINISHED` in green). It performs the PR-merged and Linear-Done
checks itself, so there's no separate scan or manual Linear confirmation step. Run it
from inside the repo, or pass `-C <dir>`.

Note the `FINISHED` rows. Worktrees showing `not an issue worktree` (recovery branches,
PR-review checkouts, experiments) are out of scope — never pass their branches on. If
nothing is `FINISHED`, report "nothing finished" with the table and stop.

### 2. Triage artifacts (per FINISHED worktree, BEFORE removal)

`issue end` removes the whole worktree, so rescue any artifacts first.

```bash
ls <WORKTREE>/pr-reviews/ <WORKTREE>/reports/ 2>/dev/null
```

If none → step 3. If present:

1. Quick triage — list files with size/date, peek at heads (HTML title / first heading)
   to identify each. Classify likely-relevant (final PR-review report, findings ledger,
   decision docs) vs likely-disposable (intermediate runs, superseded drafts, scratch
   output).
2. Interview the user with AskUserQuestion, one question per worktree: options like
   "Keep recommended set", "Keep all", "Discard all" — list the concrete filenames and
   the recommendation in the descriptions.
3. Keepers → copy to `~/Git/adaptyv/issue-archive/<ISSUE_ID>/` (create the dir),
   preserving filenames. Confirm the copy succeeded before removal.

### 3. Remove

Confirm the removal set with the user, then remove the finished worktrees
non-interactively:

```bash
issue end -y $ARGUMENTS
```

`issue end` re-checks the finished gate (so it only removes still-finished trees),
removes the worktree, deletes the local branch, prunes, and deletes `ISSUE_*<ID>*.md`
from the parent dir. It refuses to run if the cwd is inside a target worktree (cd out
first, or drive it from the parent with `-C <dir>`) and refuses a dirty tree without
`--force`.

- **Dirty tree:** show `git -C <WORKTREE> status --short` and the diff to the user, ask
  explicitly, then re-run with `--force`. Never `--force` without showing what gets
  discarded.
- **Merged but Linear not Done, and you want it gone anyway:** `issue end --pr-only`
  skips the Linear-Done gate.
- **Remove a specific non-finished worktree on purpose:** `issue end --clean-worktree
  <selector>` (issue id, branch, or path) bypasses the finished gate for that selection.

### 4. Report

One table:

| Issue | PR | Linear | Action |
|-------|----|--------|--------|
| ENG-1234 | MERGED #3001 | Done | removed; 2 artifacts archived |
| DBI-986 | OPEN #3065 | In Progress | kept |
| ... | MERGED | In Review | kept — Linear not done |

Plus: archive locations for kept artifacts, and any worktrees skipped due to errors or a
dirty tree.

## Notes

- Both gates required — a merged PR alone is not finished — unless you pass `--pr-only`.
  When in doubt, keep.
- `issue end` only ever removes worktrees its own finished gate (or `--clean-worktree`)
  selects; detached/unknown worktrees are out of scope.
- Remote branches: leave them alone — GitHub deletes merged heads per repo settings.
