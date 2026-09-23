#!/usr/bin/env bash
# Remove a finished issue worktree, delete its branch, and remove its ISSUE_*.md files.
#
# Usage: issue-end-cleanup.sh <worktree_path> <issue_id> [--force]
#   --force  also remove a dirty worktree (discards uncommitted changes)
#
# Refuses to run if invoked from inside the worktree being removed.
set -euo pipefail

wt="${1:?usage: issue-end-cleanup.sh <worktree_path> <issue_id> [--force]}"
id="${2:?usage: issue-end-cleanup.sh <worktree_path> <issue_id> [--force]}"
force="${3:-}"

wt=$(readlink -f "$wt")
[[ -d "$wt" ]] || { echo "ERROR: worktree dir not found: $wt" >&2; exit 1; }

case "$(readlink -f "$PWD")" in
  "$wt"|"$wt"/*) echo "ERROR: cd out of $wt before removing it" >&2; exit 1 ;;
esac

common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
main=$(dirname "$common")
parent=$(dirname "$main")
branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD)

if [[ -n $(git -C "$wt" status --porcelain) && "$force" != "--force" ]]; then
  echo "ERROR: worktree has uncommitted changes; rerun with --force to discard:" >&2
  git -C "$wt" status --short >&2
  exit 2
fi

echo "Removing worktree: $wt (branch: $branch)"
git -C "$main" worktree remove ${force:+--force} "$wt"
git -C "$main" worktree prune

if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$main" branch -D "$branch" \
    && echo "Deleted branch: $branch" \
    || echo "NOTE: could not delete branch $branch" >&2
fi

shopt -s nullglob
files=("$parent"/ISSUE_*"$id"*.md)
if (( ${#files[@]} )); then
  rm -v -- "${files[@]}"
else
  echo "No ISSUE_*${id}*.md files found in $parent"
fi

echo "DONE: $id cleaned up"
