#!/usr/bin/env bash
# Rebase the current branch onto the latest base branch and propagate the result
# down its stack of dependent PRs.
#
# Usage: rebase-propagate.sh [base-branch]
#        rebase-propagate.sh --dupes          read-only: run only the duplicate PR scan
#
# base-branch resolves in order: the argument, 'git config base.branch', staging,
# the remote's default branch.
#
# The stack is discovered from GitHub: every open PR whose base is a branch in
# the stack becomes a child, recursively. Each branch is rebased onto its new
# parent, then every branch is pushed. Nothing is pushed until all rebases
# succeed, so a conflict leaves the remote untouched and the run resumable.
#
# Duplicate PRs are classified but never closed — that call is left to the caller.
#
# Last line of output is always: RP-RESULT: <STATUS>
#   PROPAGATED     every branch rebased and pushed
#   NOTHING-TO-DO  already on latest base, remotes already match
#   CONFLICT       stopped on conflicts, rebase IN PROGRESS, nothing pushed
#   DIRTY          uncommitted changes, nothing done
#   IN-PROGRESS    a rebase/merge was already running, nothing done
#   PROTECTED      current branch is a protected branch, nothing done
#   REJECTED       remote moved, lease refused a push
#   HOOK-MODIFIED  pre-push hook rewrote files, push failed, tree now dirty
#   PUSH-FAILED    push failed for another reason
#   DUPES-ONLY     --dupes was passed; only the duplicate scan ran
#   ERROR          preflight failed
set -uo pipefail

PROTECTED_BRANCHES="staging main master develop production release"
REMOTE=origin
MAX_DEPTH=10

dupes_only=0
if [[ "${1:-}" == "--dupes" ]]; then
  dupes_only=1
  shift
fi

say() { printf '%s\n' "$*" | tr '\r' '\n'; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  say "not inside a git repository: $PWD"
  say "RP-RESULT: ERROR"
  exit 3
}
cd "$(git rev-parse --show-toplevel)" || exit 3
git_dir=$(git rev-parse --git-dir)
state="$git_dir/rebase-propagate.state"

scan_dupes() {
  say ""
  say "== duplicate PR scan =="
  local dupes=0 rows n keep keep_base keep_title num title bref login url verdict
  for b in "${stack[@]}"; do
    rows=$(gh pr list --head "$b" --state open --limit 20 \
             --json number,title,baseRefName,author,url 2>/dev/null)
    n=$(printf '%s' "$rows" | jq 'length' 2>/dev/null)
    [[ "${n:-0}" -lt 2 ]] && continue
    keep=${pr_of[$b]:-$(printf '%s' "$rows" | jq -r 'min_by(.number).number')}
    keep_base=$(printf '%s' "$rows" | jq -r --arg k "$keep" '.[] | select(.number == ($k|tonumber)) | .baseRefName')
    keep_title=$(printf '%s' "$rows" | jq -r --arg k "$keep" '.[] | select(.number == ($k|tonumber)) | .title')
    while IFS=$'\t' read -r num title bref login url; do
      [[ "$num" == "$keep" ]] && continue
      dupes=$((dupes + 1))
      if [[ "$bref" == "$keep_base" && "$title" == "$keep_title" ]] &&
         [[ "$login" == github-actions* || "$login" == *"[bot]" ]]; then
        verdict="CLEAR-DUPE"
      else
        verdict="AMBIGUOUS"
      fi
      say "$verdict  #$num ($login) '$title' $b -> $bref   duplicate of #$keep"
      say "          $url"
    done < <(printf '%s' "$rows" | jq -r '.[] | "\(.number)\t\(.title)\t\(.baseRefName)\t\(.author.login)\t\(.url)"')
  done
  say "RP-DUPES: $dupes"
}

finish() {
  case "$1" in
    PROPAGATED | NOTHING-TO-DO | DIRTY | PROTECTED | ERROR) [[ "$dupes_only" == 0 ]] && rm -f "$state" ;;
  esac
  say "RP-RESULT: $1"
  exit "${2:-0}"
}

# ---------------------------------------------------------------- preflight

for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if [[ "$dupes_only" == 0 && -e "$git_dir/$marker" ]]; then
    say "an operation is already in progress ($marker) — nothing done"
    say ""
    git status --short --branch
    conflicted=$(git diff --name-only --diff-filter=U)
    if [[ -n "$conflicted" ]]; then
      say ""
      say "conflicted files:"
      printf '%s\n' "$conflicted" | sed 's/^/  /'
      say ""
      say "resolve, 'git add', 'git rebase --continue', then re-run this script"
    fi
    finish IN-PROGRESS 4
  fi
done

here=$(git symbolic-ref --quiet --short HEAD) || {
  say "HEAD is detached at $(git rev-parse --short HEAD); check out a branch first"
  finish ERROR 3
}

# A resumed run must re-root on the branch the original run started from. After
# 'git rebase --continue' HEAD sits on whichever child was mid-replay, and
# re-rooting there would silently drop its ancestors from the push.
resume=0
if [[ -f "$state" ]] && grep -q "^#root" "$state" &&
   awk -F'\t' '$1!~/^#/ {print $1}' "$state" | grep -qx "$here"; then
  resume=1
  root=$(awk -F'\t' '$1=="#root" {print $2; exit}' "$state")
  git rev-parse --verify --quiet "refs/heads/$root" >/dev/null || {
    say "state file names root '$root', which no longer exists — discarding it"
    rm -f "$state"
    resume=0
    root="$here"
  }
else
  rm -f "$state"
  root="$here"
fi

for p in $PROTECTED_BRANCHES; do
  if [[ "$dupes_only" == 0 && "$root" == "$p" ]]; then
    say "$root is a protected branch — refusing to rewrite and force-push it"
    finish PROTECTED 6
  fi
done

if [[ "$dupes_only" == 0 && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  say "working tree has uncommitted changes on $root:"
  say ""
  git status --short --untracked-files=no
  say ""
  say "commit or stash them, then re-run"
  finish DIRTY 5
fi

if [[ "$dupes_only" == 0 ]]; then
  say "== fetch =="
  git fetch --prune "$REMOTE" 2>&1 | tail -20
fi

base=${1:-}
if [[ "$resume" == 1 ]]; then
  base=$(awk -F'\t' '$1=="#root" {print $3; exit}' "$state")
fi
[[ -z "$base" ]] && base=$(git config --get base.branch)
if [[ -z "$base" ]]; then
  if git rev-parse --verify --quiet "refs/remotes/$REMOTE/staging" >/dev/null; then
    base=staging
  else
    # git writes origin/HEAD once at clone time and fetch never revisits it, so a
    # missing or renamed default branch costs one round trip to correct.
    base=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)
    if [[ -z "$base" ]]; then
      git remote set-head "$REMOTE" --auto >/dev/null 2>&1
      base=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)
    fi
  fi
fi
base=${base#"$REMOTE"/}

if [[ -z "$base" ]]; then
  say "no base branch: $REMOTE has no staging branch and no default branch"
  say "pass one as an argument, or set it for this repo:"
  say "  git config base.branch <branch>"
  finish ERROR 3
fi

git rev-parse --verify --quiet "refs/remotes/$REMOTE/$base" >/dev/null || {
  say "no such base branch: $REMOTE/$base"
  finish ERROR 3
}

# ---------------------------------------------------------------- stack

# Probe repo resolution, not just auth: an authenticated gh still fails to list
# PRs when the remote is not a GitHub repo, and that must not look like an
# empty stack.
gh_ok=1
gh_repo=$(gh repo view --json nameWithOwner 2>/dev/null | jq -r '.nameWithOwner // empty')
[[ -z "$gh_repo" ]] && gh_ok=0

declare -a stack=("$root")
declare -A parent_of=() pr_of=()

if [[ "$resume" == 1 ]]; then
  stack=()
  # '-' is the placeholder for an empty field: tab is an IFS whitespace
  # character, so read would otherwise collapse two adjacent tabs into one and
  # shift every later field left.
  while IFS=$'\t' read -r b _tip p pr; do
    [[ "$b" == \#* || -z "$b" ]] && continue
    stack+=("$b")
    [[ "$p" != "-" ]] && parent_of[$b]="$p"
    [[ "$pr" != "-" ]] && pr_of[$b]="$pr"
  done <"$state"
elif [[ "$gh_ok" == 1 ]]; then
  frontier=("$root")
  depth=0
  while [[ ${#frontier[@]} -gt 0 && $depth -lt $MAX_DEPTH ]]; do
    next=()
    for b in "${frontier[@]}"; do
      kids=$(gh pr list --base "$b" --state open --limit 50 \
               --json number,headRefName 2>/dev/null \
             | jq -r '.[] | "\(.headRefName)\t\(.number)"')
      while IFS=$'\t' read -r kb kn; do
        [[ -z "$kb" ]] && continue
        [[ -n "${parent_of[$kb]:-}" ]] && continue
        [[ "$kb" == "$root" ]] && continue
        git rev-parse --verify --quiet "refs/heads/$kb" >/dev/null || {
          say "note: PR #$kn targets $b from $kb, but there is no local branch $kb — skipping it"
          continue
        }
        parent_of[$kb]="$b"
        pr_of[$kb]="$kn"
        stack+=("$kb")
        next+=("$kb")
      done <<<"$kids"
    done
    frontier=("${next[@]}")
    depth=$((depth + 1))
  done
  rootpr=$(gh pr list --head "$root" --state open --limit 10 --json number 2>/dev/null | jq -r '.[0].number // empty')
  [[ -n "$rootpr" ]] && pr_of[$root]="$rootpr"
else
  say "NOTE: gh could not resolve a GitHub repo for this remote (unavailable,"
  say "      unauthenticated, or not a GitHub remote). No PR stack was discovered,"
  say "      so ONLY $root was handled. Dependent PRs, if any, were NOT propagated."
fi

say ""
say "== stack =="
say "base: $REMOTE/$base  ($(git log --oneline -1 "$REMOTE/$base"))"
for b in "${stack[@]}"; do
  p=${parent_of[$b]:-$REMOTE/$base}
  say "  $b -> $p${pr_of[$b]:+  (PR #${pr_of[$b]})}"
done

if [[ "$dupes_only" == 1 ]]; then
  [[ "$gh_ok" == 0 ]] && finish ERROR 3
  scan_dupes
  finish DUPES-ONLY 0
fi

# ---------------------------------------------------------------- old tips

if [[ "$resume" == 1 ]]; then
  say ""
  say "resuming the run started on $root (old tips come from the state file)"
else
  printf '#root\t%s\t%s\n' "$root" "$base" >"$state"
  for b in "${stack[@]}"; do
    printf '%s\t%s\t%s\t%s\n' "$b" "$(git rev-parse "$b")" "${parent_of[$b]:--}" "${pr_of[$b]:--}" >>"$state"
  done
fi
oldtip() { awk -F'\t' -v b="$1" '$1==b {print $2; exit}' "$state"; }

# ---------------------------------------------------------------- rebase

say ""
say "== rebase =="
for b in "${stack[@]}"; do
  if [[ "$b" == "$root" ]]; then
    new_parent="$REMOTE/$base"
    old_parent=""
  else
    new_parent="${parent_of[$b]}"
    old_parent=$(oldtip "$new_parent")
  fi

  if git merge-base --is-ancestor "$new_parent" "$b" 2>/dev/null; then
    say "$b: already on top of $new_parent — skipping"
    continue
  fi

  if [[ -z "$old_parent" ]]; then
    say "$b: rebase onto $new_parent"
    out=$(git rebase "$new_parent" "$b" 2>&1)
    rc=$?
  else
    say "$b: rebase --onto $new_parent ${old_parent:0:9} (its old parent tip)"
    out=$(git rebase --onto "$new_parent" "$old_parent" "$b" 2>&1)
    rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    say "$out"
    say ""
    say "conflicted files on $b:"
    git diff --name-only --diff-filter=U | sed 's/^/  /'
    say ""
    say "stopped while applying: $(git log --oneline -1 REBASE_HEAD 2>/dev/null)"
    todo="$git_dir/rebase-merge/git-rebase-todo"
    if [[ -f "$todo" ]]; then
      say "still queued on $b: $(grep -cvE '^[[:space:]]*(#|$)' "$todo") commit(s)"
    fi
    remaining=()
    seen=0
    for x in "${stack[@]}"; do
      [[ "$x" == "$b" ]] && seen=1 && continue
      [[ $seen == 1 ]] && remaining+=("$x")
    done
    say "branches still waiting behind it: ${remaining[*]:-none}"
    say ""
    say "NOTHING HAS BEEN PUSHED — the remote is untouched."
    say "resolve, 'git add', 'git rebase --continue', then re-run this script;"
    say "it resumes from here and pushes the whole stack once every rebase lands."
    say "('git rebase --abort' backs out this branch only; re-running then restarts.)"
    finish CONFLICT 10
  fi
  say "  ok: $(git log --oneline -1 "$b")"
done

# ---------------------------------------------------------------- push

git switch --quiet "$root" || finish ERROR 3

say ""
say "== push =="
pushed=()
for b in "${stack[@]}"; do
  if [[ "$(git rev-parse "$b")" == "$(git rev-parse "$REMOTE/$b" 2>/dev/null)" ]]; then
    say "$b: remote already matches — skipping"
    continue
  fi
  if git rev-parse --verify --quiet "refs/remotes/$REMOTE/$b" >/dev/null; then
    push_out=$(git push --force-with-lease --force-if-includes "$REMOTE" "$b:$b" 2>&1)
    rc=$?
  else
    push_out=$(git push --set-upstream "$REMOTE" "$b:$b" 2>&1)
    rc=$?
  fi
  say "$b: $(printf '%s' "$push_out" | tail -2 | tr '\n' ' ')"
  if [[ $rc -ne 0 ]]; then
    say ""
    say "$push_out"
    say ""
    say "pushed so far: ${pushed[*]:-none}"
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
      say "the pre-push hook rewrote files on $b — tree is now dirty:"
      git status --short --untracked-files=no
      finish HOOK-MODIFIED 22
    fi
    if printf '%s' "$push_out" | grep -qiE 'stale info|force-with-lease|force-if-includes|non-fast-forward|fetch first|rejected'; then
      say "the remote moved since the fetch — the lease refused the push to $b"
      finish REJECTED 20
    fi
    finish PUSH-FAILED 21
  fi
  pushed+=("$b")
done

# ---------------------------------------------------------------- dupes

[[ "$gh_ok" == 1 ]] && scan_dupes

say ""
say "== result =="
for b in "${stack[@]}"; do
  say "  $b  $(git log --oneline -1 "$b")${pr_of[$b]:+  (PR #${pr_of[$b]})}"
done
say "on branch: $(git symbolic-ref --short HEAD)"
finish PROPAGATED 0
