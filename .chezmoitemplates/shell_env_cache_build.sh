[[ -f "$HOME/force_bash" || -f "$HOME/.force_bash" ]] && FORCEBASH=1

{{- /* Only cache env on personal and non-ephemeral systems */ -}}
bash_cache_dir="$HOME/.cache/bash"
if ! [[ -d "$bash_cache_dir" ]]; then
    mkdir -p "$bash_cache_dir"
    chmod 700 "$bash_cache_dir"
fi

interactive_cache="$HOME/.cache/bash/cache_interactive.bash"
interactive_cache_extensions="$HOME/.cache/bash/cache_interactive_extensions.bash"
env_cache="$HOME/.cache/bash/cache_env.bash"

# If not running interactively, don't do anything
if [[ $- != *i* ]]; then
    if [[ ! -f "$env_cache" ]]; then
        build_bash_cache
    fi
    source "$env_cache"
    {{- if .system.is_wsl }}
    export PATH="$PATH_CLEAN:$PATH_WINDOWS"
    {{- end }}
    return 0
fi

[[ -f "$HOME/.bash_force_cache" || -f "$HOME/bash_force_cache" ]] && bash_force_cache=true || bash_force_cache=false
[[ -f "$HOME/bash_force_cache_once" ]] && bash_force_cache_once=true || bash_force_cache_once=false

last_cache=$(cat "$bash_cache_dir/last_cache" 2>/dev/null)

function build_bash_cache {
    # bash "$HOME/bash_build_env_cache.bash"
    # if [[ -s "$HOME/.cache/bash/bash_cache_env.bash" ]] && [[ "$load" = "1" ]]; then
    if [[ "$SHLVL" -ge 2 ]]; then
        if [[ $- != *i* ]]; then
            if [[ ! -f "$env_cache" ]]; then
                echo "Not running in a fresh shell, but environment Bash cache is missing."
                echo "Cache will be built, but may be dirty. Rebuild it via bash_force_cache"
            else
                source "$env_cache"
                return 0
            fi
        elif [[ ! -f "$interactive_cache" ]]; then
            echo "Not running in a fresh shell, but Bash cache is missing."
            echo "Cache will be built, but may be dirty. Rebuild it via bash_force_cache"
        else
            source "$interactive_cache"
            return 0
        fi
    fi
    echo "Building BASH cache"
    echo "#!/bin/bash" >"$env_cache"

    # add additional environment variables
    [[ -s "$HOME/.bash_env" ]] && source "$HOME/.bash_env"

    # add default make/build environment variables to optimise copmilation
    [[ -s "$HOME/.compiler_env" ]] && source "$HOME/.compiler_env"

    # Store the more basic env cache
    echo "shopt -s extglob" >>"$env_cache"

    declare -p | grep -vE '^declare -[^x]' >>"$env_cache"
    declare -p | grep -E '^declare -..? (__git_|__zoxide_)' >>"$env_cache"
    {{ if .system.is_wsl -}}
    echo "export PATH=\"$PATH:$PATH_WINDOWS\"" >>"$env_cache"
    {{- end }}

    # If not running interactively, stop here
    [[ $- != *i* ]] && return

    # Build interactive session cache
    echo "#!/bin/bash" >"$interactive_cache"
    echo "#!/bin/bash" >"$interactive_cache_extensions"

    # add alias definitions
    [[ -f "$HOME/.bash_aliases" ]] && source "$HOME/.bash_aliases"

    # Source prompt configuration if available
    [[ -f "$HOME/.bash_prompt" ]] && source "$HOME/.bash_prompt"

    # don't put duplicate lines or lines starting with space in the history.
    # See bash(1) for more options
    HISTCONTROL=ignoreboth

    # append to the history file, don't overwrite it
    shopt -s histappend

    # for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
    HISTSIZE=1000
    HISTFILESIZE=2000

    # check the window size after each command and, if necessary,
    # update the values of LINES and COLUMNS.
    shopt -s checkwinsize

    # enable auto "cd" when entering just a path
    shopt -s autocd

    # check there are no running jobs before exiting
    shopt -s checkjobs

    # enable color support of ls and also add handy aliases
    if [ -x /usr/bin/dircolors ]; then
        test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    fi

    # enable programmable completion features (you don't need to enable
    # this, if it's already enabled in /etc/bash.bashrc and /etc/profile
    # sources /etc/bash.bashrc).
    if ! shopt -oq posix; then
        if [ -f /usr/share/bash-completion/bash_completion ]; then
            source /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
            source /etc/bash_completion
        fi
    fi

    # Source configs for various programs
    # has_command starship && eval "$(starship init bash)"
    # has_command zoxide && eval "$(zoxide init bash)"

    # declare -p >"$cache"  # variables
    # variables

    {{- if .system.is_wsl }}

    function __initialize_wsl_ssh_agent {
        {{ template "shell_env_wsl.sh" . }}
    }
    __initialize_wsl_ssh_agent
    {{- end }}

    # Unset helper functions
    unset -f build_bash_cache
    # unset -f __initialize_wsl_ssh_agent

    # declare -p | grep -vE '^declare -[^x] |^declare -[^ ]*r|^declare -[-ixaA] (BASH|bash_cache_dir=|cache=|FORCEBASH|S?RANDOM|SECONDS|gem_bin_dir=)' >"$cache"
    {
        echo "shopt -s extglob"
        declare -p | grep -vE '^declare -[^x]'
        # extra variables
        # declare -p | grep -E '^declare -..? (__git_|__zoxide_)'
        declare -f # functions
        alias -p   # aliases
        shopt -p   # shell options
    } >>"$interactive_cache"

    if has_command starship; then
        starship init bash --print-full-init >>"$interactive_cache_extensions"
        echo "" >>"$interactive_cache_extensions"
        export STARSHIP_LOG=error
    fi

    if has_command sk; then
        sk --shell bash --shell-bindings >>"$interactive_cache_extensions"
    elif has_command fzf; then
        fzf --bash >>"$interactive_cache_extensions"
    fi

    has_command zoxide && zoxide init bash >>"$interactive_cache_extensions"

    date +%s >"$bash_cache_dir/last_cache"
    chmod 600 "$bash_cache_dir/last_cache"
}

if [[ "${bash_force_cache}" = "true" ]] || [[ "${bash_force_cache_once}" = "true" ]] || [[ -z "${last_cache}" ]] || (($(date +%s) - last_cache >= 86400)); then
    build_bash_cache
    if [[ "$bash_force_cache_once" = "true" ]] && [[ -f "$HOME/bash_force_cache_once" ]]; then
        rm "$HOME/bash_force_cache_once"
    fi
else
    [[ -s "$interactive_cache" ]] && source "$interactive_cache"
    {{- if .system.is_wsl }}
    __initialize_wsl_ssh_agent
    unset -f __initialize_wsl_ssh_agent
    {{- end }}
fi

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# enable gpg integration
export GPG_TTY=$(tty)
