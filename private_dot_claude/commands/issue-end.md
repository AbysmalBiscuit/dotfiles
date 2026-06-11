---
description: Find finished issue worktrees (PR merged + Linear done), triage their artifacts, then remove worktree + ISSUE_*.md files
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, mcp__linear__get_issue
---

# /issue-end

Clean up issue worktrees whose work is finished. A worktree is **finished** only when
**both**: its GitHub PR is merged **and** its Linear issue is marked Done.

Worktrees live as siblings of the main repo (`../WORKTREE_NAME`, e.g.
`/home/lev/Git/adaptyv/eng-1234-...` next to `.../monorepo`), with handoff files
`ISSUE_SUMMARY_<ID>.md` in the shared parent dir. Created by `/issue-setup`.

## Input

`$ARGUMENTS` = optional issue ID(s) to limit the cleanup to (e.g. `ENG-1234 DBI-986`).
Empty = consider all worktrees of the repo containing the current dir.

## Helper scripts

- `~/.claude/scripts/issue-end-scan.sh [dir]` — lists every worktree as TSV:
  `worktree, branch, issue_id, dirty, pr_number, pr_state, pr_url, summary_file`.
  `pr_state` ∈ MERGED | OPEN | CLOSED | NO_PR.
- `~/.claude/scripts/issue-end-cleanup.sh <worktree> <issue_id> [--force]` — removes
  the worktree, deletes its local branch, prunes, and deletes `ISSUE_*<ID>*.md` from
  the parent dir. Refuses dirty worktrees without `--force`; refuses to run from
  inside the worktree being removed.

## Steps

### 1. Scan

```bash
~/.claude/scripts/issue-end-scan.sh "$PWD"
```

Filter to candidate rows:

- `pr_state == MERGED`
- `issue_id != UNKNOWN` (skip non-issue worktrees — recovery branches, PR-review
  checkouts, experiments — and never touch them)
- if `$ARGUMENTS` given, only those issue IDs

If zero candidates: report "nothing finished" with the scan table and stop.

### 2. Confirm Linear state

For each candidate, fetch the Linear issue (`mcp__linear__get_issue` with the
`issue_id`). Finished only when the issue's state **type** is `completed` (e.g.
"Done"). Not done → skip the worktree and note "PR merged but Linear not done" in
the final report. Linear lookup fails (bad ID, no access) → skip and report; never
clean up on uncertainty.

### 3. Triage artifacts (per finished worktree, BEFORE removal)

Check for artifacts:

```bash
ls <WORKTREE>/pr-reviews/ <WORKTREE>/reports/ 2>/dev/null
```

If none → proceed to step 4.

If present:

1. Quick triage — list files with size/date, peek at heads (HTML title /
   first heading) to identify each. Classify: likely-relevant (final PR-review
   report, findings ledger, decision docs) vs likely-disposable (intermediate runs,
   superseded drafts, scratch output).
2. Interview the user with AskUserQuestion, one question per worktree:
   options like "Keep recommended set", "Keep all", "Discard all" — list the
   concrete filenames and the recommendation in the descriptions.
3. Keepers → copy to `/home/lev/Git/adaptyv/issue-archive/<ISSUE_ID>/` (create dir),
   preserving filenames. Confirm copy succeeded before removal.

### 4. Remove

If the current dir is inside a worktree about to be removed, tell the user to cd out
(or run the rest from the parent dir via `git -C`) — the cleanup script refuses
otherwise.

```bash
~/.claude/scripts/issue-end-cleanup.sh <WORKTREE> <ISSUE_ID>
```

If the script exits 2 (dirty worktree): show `git -C <WORKTREE> status --short` and
the diff to the user, and ask explicitly before re-running with `--force`. Never
`--force` without showing what gets discarded.

### 5. Report

One table:

| Issue | PR | Linear | Action |
|-------|----|--------|--------|
| ENG-1234 | MERGED #3001 | Done | removed; 2 artifacts archived |
| DBI-986 | OPEN #3065 | In Progress | kept |
| ... | MERGED | In Review | kept — Linear not done |

Plus: archive locations for kept artifacts, and any worktrees skipped due to errors.

## Notes

- Both gates required — merged PR alone is not finished. When in doubt, keep.
- Only ever remove worktrees whose branch matches an issue pattern (`abc-123`);
  detached/unknown worktrees are out of scope even with `--force` available.
- Remote branches: leave them alone — GitHub deletes merged heads per repo settings.
