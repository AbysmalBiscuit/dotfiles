#!/usr/bin/env bash
# Reset the current worktree's branch to exactly match its upstream.
#
# Fetches, then `git reset --hard @{upstream}`, discarding local commits and
# uncommitted changes. Refuses on protected branches and prompts before the
# destructive step unless -y is given.
#
# Usage: git-reset-pr-branch.sh [-C <dir>] [-y] [--clean] [-h]
#   -C <dir>   operate in <dir> instead of the current directory
#   -y         skip the confirmation prompt
#   --clean    also `git clean -fd` (remove untracked files/dirs) after reset
#   -h         show this help

set -euo pipefail

PROTECTED=(main master staging)
dir=""
assume_yes=0
do_clean=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) dir="${2:?-C needs a directory}"; shift 2 ;;
    -y|--yes) assume_yes=1; shift ;;
    --clean) do_clean=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1 (see -h)" ;;
  esac
done

[[ -n "$dir" ]] && cd "$dir"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git work tree"

branch="$(git symbolic-ref --quiet --short HEAD)" || die "detached HEAD — check out a branch first"

for p in "${PROTECTED[@]}"; do
  [[ "$branch" == "$p" ]] && die "refusing to hard-reset protected branch '$branch'"
done

# Resolve the upstream this branch tracks (usually origin/<branch>).
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" \
  || die "branch '$branch' has no upstream — set one with: git branch --set-upstream-to=origin/$branch"

remote="${upstream%%/*}"
echo "Fetching '$remote'…"
git fetch --prune "$remote"

before="$(git rev-parse HEAD)"
after="$(git rev-parse "$upstream")"

if [[ "$before" == "$after" ]]; then
  echo "Already at $upstream ($after). Nothing to reset."
  # Still honour --clean so the tree can be scrubbed even when refs match.
  if [[ "$do_clean" -eq 1 ]]; then
    echo "Cleaning untracked files…"
    git clean -fd
  fi
  exit 0
fi

echo
echo "Branch '$branch' will be reset to '$upstream'."
echo "  HEAD     $before"
echo "  upstream $after"
ahead="$(git rev-list --count "$upstream..HEAD")"
behind="$(git rev-list --count "HEAD..$upstream")"
echo "  local is $ahead commit(s) ahead, $behind behind upstream"
[[ "$ahead" -gt 0 ]] && echo "  ${ahead} local commit(s) will be discarded (recoverable via git reflog)"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "  uncommitted changes present — these WILL be lost"
fi

if [[ "$assume_yes" -ne 1 ]]; then
  read -r -p "Proceed with hard reset? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || die "aborted"
fi

git reset --hard "$upstream"

if [[ "$do_clean" -eq 1 ]]; then
  echo "Cleaning untracked files…"
  git clean -fd
fi

echo "Done. '$branch' now matches '$upstream'."
