#!/usr/bin/env bash
# Scan all issue worktrees of the repo containing <dir> and report PR state for each.
#
# Usage: issue-end-scan.sh [dir]
#   dir = anywhere inside the main repo or any of its worktrees (default: $PWD)
#
# Output: TSV with header
#   worktree  branch  issue_id  dirty  pr_number  pr_state  pr_url  summary_file
#
# pr_state is one of: MERGED | OPEN | CLOSED | NO_PR
# summary_file is the matching ISSUE_SUMMARY_<ID>.md in the worktrees' parent dir, or "-".
set -euo pipefail

start="${1:-$PWD}"

main=""
declare -a wts=() brs=()
wt="" br=""
flush() {
  if [[ -n "$wt" ]]; then
    if [[ -z "$main" ]]; then main="$wt"; else wts+=("$wt"); brs+=("${br:-DETACHED}"); fi
  fi
  wt="" br=""
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt="${line#worktree }" ;;
    "branch refs/heads/"*) br="${line#branch refs/heads/}" ;;
    "") flush ;;
  esac
done < <(git -C "$start" worktree list --porcelain)
flush

if [[ -z "$main" ]]; then
  echo "ERROR: not inside a git repo: $start" >&2
  exit 1
fi

parent=$(dirname "$main")
printf 'worktree\tbranch\tissue_id\tdirty\tpr_number\tpr_state\tpr_url\tsummary_file\n'

for i in "${!wts[@]}"; do
  w="${wts[$i]}" b="${brs[$i]}"

  id=$(grep -oiE '[a-z]+-[0-9]+' <<<"$b" | head -1 | tr '[:lower:]' '[:upper:]' || true)
  [[ -z "$id" ]] && id=$(grep -oiE '[a-z]+-[0-9]+' <<<"$(basename "$w")" | head -1 | tr '[:lower:]' '[:upper:]' || true)
  [[ -z "$id" ]] && id="UNKNOWN"

  dirty=clean
  [[ -n $(git -C "$w" status --porcelain 2>/dev/null | head -1) ]] && dirty=dirty

  pr_json="[]"
  if [[ "$b" != "DETACHED" ]]; then
    pr_json=$(cd "$main" && gh pr list --head "$b" --state all --json number,state,url --limit 1 2>/dev/null || echo "[]")
  fi
  pr_number=$(jq -r '.[0].number // "none"' <<<"$pr_json")
  pr_state=$(jq -r '.[0].state // "NO_PR"' <<<"$pr_json")
  pr_url=$(jq -r '.[0].url // "-"' <<<"$pr_json")

  sf="-"
  [[ "$id" != "UNKNOWN" && -f "$parent/ISSUE_SUMMARY_$id.md" ]] && sf="$parent/ISSUE_SUMMARY_$id.md"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$w" "$b" "$id" "$dirty" "$pr_number" "$pr_state" "$pr_url" "$sf"
done
