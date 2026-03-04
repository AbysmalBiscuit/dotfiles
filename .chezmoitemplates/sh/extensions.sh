# Source configs for various programs
if has_command starship; then
    eval "$(starship init {{ .system.shell }} --print-full-init)"
    export STARSHIP_LOG=error
fi

if has_command sk; then
    eval "$(sk --shell {{ .system.shell }} --shell-bindings)"
elif has_command fzf; then
    eval "$(fzf --{{ .system.shell }})"
fi

has_command zoxide && eval "$(zoxide init {{ .system.shell }})"
