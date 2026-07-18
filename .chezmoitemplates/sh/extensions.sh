# Source configs for various programs
{{ if lookPath "starship" -}}
eval "$(starship init {{ .shell }} --print-full-init)"
export STARSHIP_LOG=error
{{ end }}
{{ if lookPath "sk" -}}
eval "$(sk --shell {{ .shell }} --shell-bindings)"
{{ else if lookPath "fzf" -}}
eval "$(fzf --{{ .shell }})"
{{ end }}
{{ if lookPath "zoxide" -}}
eval "$(zoxide init {{ .shell }})"
{{ end }}
