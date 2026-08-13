#!/bin/sh
# Re-home this alacritree session in the sidebar to wherever Claude Code is
# working. ALACRITREE_SESSION_ID is only set for shells spawned inside
# alacritree, so this is a no-op elsewhere.
#
# CwdChanged only fires for a Bash `cd` — the /cd command relocates the session
# without emitting any event. SessionStart covers starting Claude in a worktree
# the terminal was not opened in, and UserPromptSubmit picks /cd up on the next
# prompt. Every run re-sends unconditionally, so `/cd .` forces a resync when
# the sidebar has drifted.
[ -n "$ALACRITREE_SESSION_ID" ] || exit 0

# CwdChanged carries the destination in new_cwd; its base `cwd` field still
# holds the directory being left.
cwd=$(jq -r '.new_cwd // .cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

alacritree=$(command -v alacritree || command -v alacritree.exe) || exit 0
"$alacritree" session move "$ALACRITREE_SESSION_ID" "$cwd" >/dev/null 2>&1 && exit 0

# A worktree created since alacritree last scanned its project is absent from
# the sidebar and the move is refused. Re-scan the owning project and retry.
gitdir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
"$alacritree" project refresh "$(dirname "$gitdir")" >/dev/null 2>&1 || exit 0
"$alacritree" session move "$ALACRITREE_SESSION_ID" "$cwd" >/dev/null 2>&1 || true
