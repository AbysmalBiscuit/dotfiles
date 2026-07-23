#!/bin/sh
# Re-home this alacritree session in the sidebar when the Claude Code working
# directory moves. ALACRITREE_SESSION_ID is only set for shells spawned inside
# alacritree, so this is a no-op elsewhere.
#
# CwdChanged only fires for a Bash `cd`; the /cd command relocates the session
# without emitting it. Running on UserPromptSubmit too picks /cd up on the next
# prompt, and the recorded directory keeps that from re-sending every time.
[ -n "$ALACRITREE_SESSION_ID" ] || exit 0

# CwdChanged carries the destination in new_cwd; its base `cwd` field still
# holds the directory being left.
cwd=$(jq -r '.new_cwd // .cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

state="${TMPDIR:-/tmp}/alacritree-follow-$ALACRITREE_SESSION_ID"
sent=
[ -r "$state" ] && IFS= read -r sent <"$state"
[ "$sent" = "$cwd" ] && exit 0

alacritree=$(command -v alacritree || command -v alacritree.exe) || exit 0
"$alacritree" session move "$ALACRITREE_SESSION_ID" "$cwd" >/dev/null 2>&1 || exit 0
printf '%s\n' "$cwd" >"$state"
