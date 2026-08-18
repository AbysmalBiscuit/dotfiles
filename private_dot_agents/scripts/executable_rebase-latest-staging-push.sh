#!/usr/bin/env bash
# Rebase the current branch on the latest base branch and push it.
#
# Usage: rlsp.sh [base-branch]        base-branch defaults to staging, then the remote HEAD
#
# Runs the whole happy path unattended: fetch, rebase, push with lease. Stops
# before anything ambiguous (conflicts, dirty tree, protected branch, rejected
# push) and reports enough state for a caller to take over.
#
# Last line of output is always: RLSP-RESULT: <STATUS>
#   PUSHED          rebased and pushed
#   UP-TO-DATE      already on latest base, remote already matches
#   CONFLICT        rebase stopped on conflicts, rebase still IN PROGRESS
#   DIRTY           uncommitted changes, nothing done
#   IN-PROGRESS     a rebase/merge/cherry-pick was already running, nothing done
#   NO-COMMITS      branch has no commits of its own, nothing to push
#   PROTECTED       current branch is a protected branch, nothing done
#   INSTALL-FAILED  bun.lock moved in the rebase and 'bun install' failed
#   HOOK-MODIFIED   pre-push hook rewrote files, push failed, tree now dirty
#   REJECTED        remote moved, lease refused the push
#   PUSH-FAILED     push failed for another reason (hook failure, network, auth)
#   ERROR           preflight failed (not a repo, detached HEAD, no such base)
set -uo pipefail

PROTECTED_BRANCHES="staging main master develop production release"
REMOTE=origin

say() { printf '%s\n' "$*" | tr '\r' '\n'; }
finish() { say "RLSP-RESULT: $1"; exit "${2:-0}"; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  say "not inside a git repository: $PWD"
  finish ERROR 3
}
cd "$(git rev-parse --show-toplevel)" || finish ERROR 3

# An interrupted rebase leaves HEAD detached, so this has to come before the
# detached-HEAD check or a mid-conflict re-run reports the wrong thing.
git_dir=$(git rev-parse --git-dir)
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if [[ -e "$git_dir/$marker" ]]; then
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

branch=$(git symbolic-ref --quiet --short HEAD) || {
  say "HEAD is detached at $(git rev-parse --short HEAD); check out a branch first"
  finish ERROR 3
}

for p in $PROTECTED_BRANCHES; do
  if [[ "$branch" == "$p" ]]; then
    say "$branch is a protected branch — refusing to rewrite and force-push it"
    say ""
    git status --short --branch
    finish PROTECTED 6
  fi
done

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  say "working tree has uncommitted changes on $branch:"
  say ""
  git status --short --untracked-files=no
  say ""
  say "commit or stash them, then re-run"
  finish DIRTY 5
fi

say "== fetch =="
git fetch --prune "$REMOTE" 2>&1 | tail -20

base=${1:-}
if [[ -z "$base" ]]; then
  if git rev-parse --verify --quiet "refs/remotes/$REMOTE/staging" >/dev/null; then
    base=staging
  else
    base=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)
    base=${base#"$REMOTE"/}
  fi
fi
base=${base#"$REMOTE"/}
base_ref="$REMOTE/$base"

git rev-parse --verify --quiet "refs/remotes/$base_ref" >/dev/null || {
  say "no such base branch: $base_ref"
  finish ERROR 3
}

say ""
say "== rebase $branch onto $base_ref =="
say "base tip:   $(git log --oneline -1 "$base_ref")"
say "branch tip: $(git log --oneline -1 HEAD)"
say "commits to replay:"
git log --oneline "$base_ref..HEAD" | sed 's/^/  /'

# node_modules tracks whatever was last installed; the pre-rebase blob is the
# closest proxy for that, so compare against it rather than the base branch.
lock_file=""
lock_before=""
for candidate in bun.lock bun.lockb; do
  if git cat-file -e "HEAD:$candidate" 2>/dev/null; then
    lock_file=$candidate
    lock_before=$(git rev-parse "HEAD:$candidate")
    break
  fi
done

if ! rebase_out=$(git rebase "$base_ref" 2>&1); then
  say "$rebase_out"
  say ""
  say "conflicted files:"
  git diff --name-only --diff-filter=U | sed 's/^/  /'
  say ""
  todo="$git_dir/rebase-merge/git-rebase-todo"
  if [[ -f "$todo" ]]; then
    remaining=$(grep -cvE '^[[:space:]]*(#|$)' "$todo")
  else
    remaining='?'
  fi
  say "stopped while applying: $(git log --oneline -1 REBASE_HEAD 2>/dev/null)"
  say "still queued after this one: $remaining commit(s)"
  say ""
  say "the rebase is IN PROGRESS — resolve, 'git add', 'git rebase --continue',"
  say "then re-run this script to push (or 'git rebase --abort' to back out)"
  finish CONFLICT 10
fi
say "$rebase_out"

if [[ -n "$lock_file" ]]; then
  lock_after=$(git rev-parse "HEAD:$lock_file" 2>/dev/null || true)
  if [[ "$lock_before" != "$lock_after" ]]; then
    say ""
    say "== bun install ($lock_file moved in the rebase) =="
    if ! command -v bun >/dev/null 2>&1; then
      say "bun is not on PATH — skipped; node_modules is stale against $lock_file"
    elif install_out=$(bun install 2>&1); then
      printf '%s\n' "$install_out" | tail -5
      # A rewritten lockfile means the committed one does not survive a clean
      # install; the push would carry a tree nobody can reproduce.
      if [[ -n "$(git status --porcelain --untracked-files=no -- "$lock_file")" ]]; then
        say ""
        say "warning: the install rewrote $lock_file — commit it or investigate before pushing"
      fi
    else
      printf '%s\n' "$install_out" | tail -20
      say ""
      say "the rebase succeeded and is committed; only the install failed."
      say "fix the cause and re-run this script — it will resume at the push"
      finish INSTALL-FAILED 23
    fi
  fi
fi

if [[ "$(git rev-list --count "$base_ref..HEAD")" == "0" ]]; then
  say ""
  say "$branch has no commits of its own on top of $base_ref — nothing to push"
  finish NO-COMMITS 0
fi

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)

if [[ -n "$upstream" ]] && [[ "$(git rev-parse HEAD)" == "$(git rev-parse "$upstream")" ]]; then
  say ""
  say "$branch already matches $upstream — nothing to push"
  finish UP-TO-DATE 0
fi

say ""
say "== push =="
if [[ -n "$upstream" ]]; then
  push_cmd=(git push --force-with-lease --force-if-includes "$REMOTE" "HEAD:$branch")
else
  say "no upstream yet — publishing $branch"
  push_cmd=(git push --set-upstream "$REMOTE" "HEAD:$branch")
fi
say "${push_cmd[*]}"

if push_out=$("${push_cmd[@]}" 2>&1); then
  say "$push_out"
  say ""
  git status --short --branch
  say "$(git log --oneline -1 HEAD)"
  finish PUSHED 0
fi

say "$push_out"
say ""

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  say "the pre-push hook rewrote files — push aborted and the tree is now dirty:"
  say ""
  git status --short --untracked-files=no
  say ""
  say "decide whether these belong in a new commit or amended into an existing one,"
  say "then re-run this script"
  finish HOOK-MODIFIED 22
fi

if printf '%s' "$push_out" | grep -qiE 'stale info|force-with-lease|force-if-includes|non-fast-forward|fetch first|rejected'; then
  say "the remote moved since the last fetch — the lease refused the push"
  say "someone else may have pushed to $REMOTE/$branch; inspect before overriding"
  finish REJECTED 20
fi

say "push failed — see the output above (pre-push hook, network, or auth)"
finish PUSH-FAILED 21
