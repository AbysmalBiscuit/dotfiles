#!/usr/bin/env bash
# Read-only recon for /issue-review: work out which branch of the workflow
# applies and gather everything needed to run `issue review request`.
#
# Usage: issue-review-recon.sh [reviewer-alias]     alias defaults to igor
#
# Mutates nothing — no commit, no push, no `issue review request`. Those need a
# human-authored commit message, PR body, or Slack summary, so they stay with
# the caller.
#
# Last two lines are always:
#   IR-BRANCH: A | B | STOP
#   IR-RESULT: <STATUS>
#     READY               proceed with the branch named in IR-BRANCH
#     NOTHING-NEW         PR is open but the reviewer has already seen HEAD
#     PR-MERGED           nothing to review
#     PR-CLOSED           nothing to review
#     PROTECTED           on a base branch, not a feature branch
#     NOT-ISSUE-WORKTREE  no issue record, so the PR templates cannot render
#     UNKNOWN-REVIEWER    the alias is not in the devkit config
#     ERROR               preflight failed
set -uo pipefail

DEFAULT_REVIEWER=igor
PROTECTED_BRANCHES="staging main master develop production release"
FULL_DIFF_MAX_LINES=400

say() { printf '%s\n' "$*" | tr '\r' '\n'; }
finish() {
  say ""
  say "IR-BRANCH: $2"
  say "IR-RESULT: $1"
  exit "${3:-0}"
}

git rev-parse --git-dir >/dev/null 2>&1 || {
  say "not inside a git repository: $PWD"
  finish ERROR STOP 3
}
cd "$(git rev-parse --show-toplevel)" || exit 3

branch=$(git symbolic-ref --quiet --short HEAD) || {
  say "HEAD is detached at $(git rev-parse --short HEAD); check out the issue branch first"
  finish ERROR STOP 3
}

for p in $PROTECTED_BRANCHES; do
  if [[ "$branch" == "$p" ]]; then
    say "on $branch — that is a base branch, not an issue worktree feature branch"
    finish PROTECTED STOP 6
  fi
done

# ---------------------------------------------------------------- reviewer

alias_in=${1:-}
[[ -z "$alias_in" ]] && alias_in="$DEFAULT_REVIEWER"
config=${DEVKIT_CONFIG:-$HOME/.config/devkit/config.toml}

gh_handle="" slack_id=""
if [[ -f "$config" ]]; then
  eval "$(awk -v want="[people.$alias_in]" '
    $0 == want { inside = 1; next }
    /^\[/      { inside = 0 }
    inside && /^[[:space:]]*github[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|"[[:space:]]*$/, ""); print "gh_handle=\"" $0 "\"" }
    inside && /^[[:space:]]*slack[[:space:]]*=/  { gsub(/.*=[[:space:]]*"|"[[:space:]]*$/, ""); print "slack_id=\"" $0 "\"" }
  ' "$config")"
fi

# ---------------------------------------------------------------- context

info=$(issue info --json 2>/dev/null)
if [[ -n "$info" ]]; then
  issue_id=$(printf '%s' "$info" | jq -r '.issue_id // empty')
  worktree=$(printf '%s' "$info" | jq -r '.worktree // empty')
  pr_number=$(printf '%s' "$info" | jq -r '.pr_number // empty')
  pr_state=$(printf '%s' "$info" | jq -r '.pr_state // "NO_PR"')
  pr_url=$(printf '%s' "$info" | jq -r '.pr_url // empty')
  linear_name=$(printf '%s' "$info" | jq -r '.linear_name // empty')
else
  issue_id="" worktree="$PWD" pr_number="" pr_state="" pr_url="" linear_name=""
fi

prjson=$(gh pr view --json number,state,url,baseRefName,reviewRequests,latestReviews 2>/dev/null)
if [[ -n "$prjson" ]]; then
  pr_number=$(printf '%s' "$prjson" | jq -r '.number // empty')
  pr_state=$(printf '%s' "$prjson" | jq -r '.state // empty')
  pr_url=$(printf '%s' "$prjson" | jq -r '.url // empty')
  base=$(printf '%s' "$prjson" | jq -r '.baseRefName // empty')
fi
[[ -z "${pr_state:-}" ]] && pr_state=NO_PR
if [[ -z "${base:-}" ]]; then
  base=staging
  git rev-parse --verify --quiet refs/remotes/origin/staging >/dev/null || {
    base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    base=${base#origin/}
  }
fi

say "== context =="
say "worktree: $worktree"
say "branch:   $branch"
say "issue:    ${issue_id:-(none found)}${linear_name:+   Linear: $linear_name}"
say "base:     $base"
say "reviewer: $alias_in${gh_handle:+   github: $gh_handle}${slack_id:+   slack: $slack_id}"

if [[ -z "$gh_handle" ]]; then
  say ""
  say "the alias '$alias_in' has no [people.$alias_in] entry in $config"
  say "known aliases: $(awk -F'[][.]' '/^\[people\./ {print $3}' "$config" 2>/dev/null | paste -sd' ')"
  finish UNKNOWN-REVIEWER STOP 7
fi

if [[ -z "$issue_id" ]]; then
  say ""
  say "no issue record for this worktree — the pr_title/pr_body templates render"
  say "with strict-undefined and will fail without one. Run this from inside an"
  say "issue worktree, or pass the title/body without relying on the templates."
  finish NOT-ISSUE-WORKTREE STOP 8
fi

# ---------------------------------------------------------------- pr state

say ""
say "== pr =="
case "$pr_state" in
  NO_PR)
    say "no PR for $branch — this is the first review request"
    ;;
  OPEN)
    say "#$pr_number OPEN  $pr_url"
    printf '%s' "$prjson" | jq -r '
      (.reviewRequests // []) as $rr |
      (if ($rr|length) > 0
       then "pending review requests: " + ([$rr[] | (.login // .name // "?")] | join(", "))
       else "pending review requests: none" end)'
    printf '%s' "$prjson" | jq -r '
      (.latestReviews // []) | if length == 0 then "latest reviews: none submitted yet"
      else "latest reviews:", (.[] | "  \(.author.login) \(.state) at \(.commit.oid[0:9]) (\(.submittedAt))") end'
    ;;
  MERGED | CLOSED)
    say "#$pr_number $pr_state  $pr_url"
    say ""
    say "there is nothing to review on a $pr_state PR"
    finish "PR-$pr_state" STOP 9
    ;;
  *)
    say "unexpected PR state '$pr_state'"
    finish ERROR STOP 3
    ;;
esac

# ---------------------------------------------------------------- tree

uncommitted=$(git status --porcelain --untracked-files=no)
untracked=$(git ls-files --others --exclude-standard)
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
unpushed=""
[[ -n "$upstream" ]] && unpushed=$(git log --oneline "$upstream..HEAD")

say ""
say "== working tree =="
if [[ -z "$uncommitted$untracked" ]]; then
  say "clean"
else
  git status --short
fi
if [[ -z "$upstream" ]]; then
  say "no upstream yet — the branch has never been pushed"
elif [[ -n "$unpushed" ]]; then
  say "unpushed commits:"
  printf '%s\n' "$unpushed" | sed 's/^/  /'
else
  say "no unpushed commits"
fi

# ---------------------------------------------------------------- changes

last_reviewed=""
if [[ "$pr_state" == "OPEN" ]]; then
  last_reviewed=$(printf '%s' "$prjson" |
    jq -r '(.latestReviews // []) | max_by(.submittedAt) | .commit.oid // empty' 2>/dev/null)
fi

if [[ "$pr_state" == "OPEN" && -n "$last_reviewed" ]]; then
  since="$last_reviewed"
  since_label="the reviewer's last review (${last_reviewed:0:9})"
elif [[ "$pr_state" == "OPEN" ]]; then
  since="${upstream:-origin/$base}"
  since_label="the pushed tip (no review submitted yet)"
else
  since="origin/$base"
  since_label="origin/$base"
fi

if [[ "$pr_state" == "OPEN" && -n "$last_reviewed" ]] &&
   [[ "$(git rev-parse HEAD)" == "$(git rev-parse "$last_reviewed" 2>/dev/null)" ]] &&
   [[ -z "$uncommitted$untracked" ]]; then
  say ""
  say "HEAD is exactly what $alias_in last reviewed and the tree is clean —"
  say "there is nothing new to re-review."
  finish NOTHING-NEW STOP 0
fi

say ""
say "== changes to review (since $since_label) =="
commits=$(git log --reverse --format='%h %s' "$since..HEAD" 2>/dev/null)
if [[ -n "$commits" ]]; then
  say "commits:"
  printf '%s\n' "$commits" | sed 's/^/  /'
else
  say "commits: none (all the work is still uncommitted)"
fi
say ""
say "diffstat vs $since (committed):"
git diff --stat "$since..HEAD" 2>/dev/null | sed 's/^/  /'
if [[ -n "$uncommitted" ]]; then
  say ""
  say "diffstat of uncommitted changes:"
  git diff --stat HEAD | sed 's/^/  /'
fi
if [[ -n "$untracked" ]]; then
  say ""
  say "untracked files (NOT in any diff below — decide whether they belong):"
  printf '%s\n' "$untracked" | sed 's/^/  /'
fi

total=$(( $(git diff "$since..HEAD" 2>/dev/null | wc -l) + $(git diff HEAD | wc -l) ))
say ""
if [[ "$total" -le "$FULL_DIFF_MAX_LINES" ]]; then
  say "full diff ($total lines):"
  git diff "$since..HEAD" 2>/dev/null
  [[ -n "$uncommitted" ]] && { say "--- uncommitted ---"; git diff HEAD; }
  for f in $untracked; do
    say "--- untracked: $f ---"
    cat "$f"
  done
else
  say "full diff omitted: $total lines (> $FULL_DIFF_MAX_LINES). Read the files you need."
fi

# ---------------------------------------------------------------- next

say ""
say "== next =="
if [[ "$pr_state" == "NO_PR" ]]; then
  say "Branch A. Commit anything pending, then:"
  say ""
  say "  issue review request --to \"$alias_in\" \\"
  say "    --pr-title \"<conventional-commit subject, no [$issue_id] — the template adds it>\" \\"
  say "    --pr-body  \"<what changed + why, no 'Closes $issue_id' — the template adds it>\" \\"
  say "    \"<one-line Slack ask, no PR link — the template appends it>\""
  say ""
  say "Add --arg linear_magic_word=Ref if merging this PR must NOT close $issue_id."
  finish READY A 0
else
  say "Branch B. Commit anything pending, then:"
  say ""
  say "  issue review request --to \"$alias_in\" \\"
  say "    \"addressed your comments: <1-2 sentence summary>. Mind taking another look? 🙏\""
  say ""
  say "No --pr-title/--pr-body: PR #$pr_number already exists."
  finish READY B 0
fi
