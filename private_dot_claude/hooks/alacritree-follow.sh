# Re-home this alacritree session in the sidebar when the Claude Code
# working directory moves (Bash cd or /cd). ALACRITREE_SESSION_ID is only
# set for shells spawned inside alacritree, so this is a no-op elsewhere.
[ -n "$ALACRITREE_SESSION_ID" ] || exit 0
cwd=$(jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0
alacritree session move "$ALACRITREE_SESSION_ID" "$cwd" >/dev/null 2>&1 || true
