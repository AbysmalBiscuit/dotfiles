[[ -f "$HOME/debug_shell_startup" ]] && debug_shell_startup=true || debug_shell_startup=false

if [[ "$debug_shell_startup" = "true" ]]; then
    start="$(date +%s.%N)"
fi
