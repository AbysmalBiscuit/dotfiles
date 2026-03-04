{{- $shell := .system.shell -}}
{{- /* Only cache env on personal and non-ephemeral systems */ -}}
sh_cache_dir="$HOME/.cache/{{ $shell }}"
if ! [[ -d "$sh_cache_dir" ]]; then
    mkdir -p "$sh_cache_dir"
    chmod 700 "$sh_cache_dir"
fi

{{- /* env_cache is sourced for non-interactive sessions */}}
{{- /* env_cache stores various environment variables */}}
env_cache="$sh_cache_dir/env.{{ $shell }}"

{{- /* interactive_cache* are only sourced in interactive sessions */}}
{{- /* interactive_cache contains the environment configuration for interactive sessions */}}
interactive_cache="$sh_cache_dir/interactive.{{ $shell }}"

# If not running interactively, don't do anything
if [[ $- != *i* ]]; then
    if [[ ! -f "$env_cache" ]]; then
        build_env_cache
    fi
    source "$env_cache"
    return 0
fi

[[ -f "$HOME/.sh_force_cache" || -f "$HOME/sh_force_cache" ]] && sh_force_cache=true || sh_force_cache=false
[[ -f "$HOME/sh_force_cache_once" ]] && sh_force_cache_once=true || sh_force_cache_once=false

last_cache=$(cat "$sh_cache_dir/last" 2>/dev/null)

function build_env_cache {
    if [[ "$SHLVL" -ge 2 ]]; then
        if [[ $- != *i* ]]; then
            if [[ ! -f "$env_cache" ]]; then
                echo "Not running in a fresh shell, but SH environment cache is missing."
                echo "Cache will be built, but may be dirty. Rebuild it via sh_force_cache"
            else
                source "$env_cache"
                return 0
            fi
        elif [[ ! -f "$interactive_cache" ]]; then
            echo "Not running in a fresh shell, but SH cache is missing."
            echo "Cache will be built, but may be dirty. Rebuild it via sh_force_cache"
        else
            source "$interactive_cache"
            return 0
        fi
    fi
    echo "Building {{ $shell }} cache"
    echo "#!/bin/{{ $shell }}" >"$env_cache"

    {{- if eq .system.shell "bash" }}
    [[ -f "$HOME/.sh_env" ]] && source "$HOME/.sh_env"
    {{- end }}

    {{- if eq .system.shell "bash" }}
    # Store the more basic env cache
    echo "shopt -s extglob" >>"$env_cache"
    {{- end }}

    declare -p | grep -vE '^declare -[^x]' >>"$env_cache"
    declare -p | grep -E '^declare -..? (__git_|__zoxide_)' >>"$env_cache"

    {{ template "sh/env_wsl.sh" . }}

    # If not running interactively, stop here
    [[ $- != *i* ]] && return

    # Build interactive session cache
    echo "#!/bin/{{ $shell }}" >"$interactive_cache"

    # add alias definitions
    [[ -f "$HOME/.sh_aliases" ]] && source "$HOME/.sh_aliases"

    {{ if eq .system.shell "bash" -}}
    {{ template "bash/rc.bash" . }}
    {{- else if eq .system.shell "zsh" -}}
    {{ template "zsh/rc.zsh" . }}
    {{- end }}

    # Unset cache builder function
    unset -f build_env_cache

    # declare -p | grep -vE '^declare -[^x] |^declare -[^ ]*r|^declare -[-ixaA] (BASH|sh_cache_dir=|cache=|FORCEBASH|S?RANDOM|SECONDS|gem_bin_dir=)' >"$cache"
    {
        {{ if eq .system.shell "bash" -}}
        declare -p | grep -vE '^declare -[^x]'
        alias -p
        declare -f
        shopt -p
        {{- else if eq .system.shell "zsh" -}}
        export -p
        alias -L
        echo "'builtin' 'unsetopt' 'aliases'"
        declare -f
        echo "'builtin' 'setopt' 'aliases'"
        {{- end }}
    } >>"$interactive_cache"

    if has_command starship; then
        starship init {{ $shell }} --print-full-init >>"$interactive_cache"
        echo "" >>"$interactive_cache"
        echo "export STARSHIP_LOG=error" >>"$interactive_cache"
    fi

    if has_command sk; then
        sk --shell {{ $shell }} --shell-bindings >>"$interactive_cache"
    elif has_command fzf; then
        fzf --{{ $shell }} >>"$interactive_cache"
    fi

    has_command zoxide && zoxide init {{ $shell }} >>"$interactive_cache"

    date +%s >"$sh_cache_dir/last_cache"
    chmod 600 "$sh_cache_dir/last_cache"
}

if [[ "${sh_force_cache}" = "true" ]] || [[ "${sh_force_cache_once}" = "true" ]] || [[ -z "${last_cache}" ]] || (($(date +%s) - last_cache >= 86400)); then
    build_env_cache
    if [[ "$sh_force_cache_once" = "true" ]] && [[ -f "$HOME/sh_force_cache_once" ]]; then
        rm "$HOME/sh_force_cache_once"
    fi
else
    source "$interactive_cache"
    {{ template "sh/env_wsl.sh" . }}
fi

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
