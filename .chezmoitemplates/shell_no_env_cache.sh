[[ -f "$HOME/force_bash" || -f "$HOME/.force_bash" ]] && FORCEBASH=1

# add additional environment variables
[[ -s "$HOME/.bash_env" ]] && source "$HOME/.bash_env"

# add default make/build environment variables to optimise copmilation
[[ -s "$HOME/.compiler_env" ]] && source "$HOME/.compiler_env"

# If not running interactively, stop here
[[ $- != *i* ]] && return

{{ template "shell_env_wsl.sh" . }}

# enable gpg integration
export GPG_TTY=$(tty)

# Starting fish shell, and make sure to exit after
if [[ -x $(command -v fish 2>/dev/null) && -z "$BASH_EXECUTION_STRING" && "$FORCEBASH" != "1" ]]; then
    exec fish
fi

# if grep -qv 'fish' /proc/$PPID/comm && [[ ${SHLVL} == [1,2] && "$FORCEBASH" != "1" ]]; then
#     shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=''
#     echo $LOGIN_OPTION
#     exec fish $LOGIN_OPTION
# fi

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

# add alias definitions
[[ -f "$HOME/.bash_aliases" ]] && source "$HOME/.bash_aliases"

# Source prompt configuration if available
[[ -f "$HOME/.bash_prompt" ]] && source "$HOME/.bash_prompt"

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
if has_command starship; then
    eval "$(starship init bash --print-full-init)"
    export STARSHIP_LOG=error
fi

if has_command sk; then
    eval "$(sk --shell bash --shell-bindings)"
elif has_command fzf; then
    eval "$(fzf --bash)"
fi

has_command zoxide && eval "$(zoxide init bash)"

if [[ "$debug_shell_startup" = "true" ]]; then
    end=$(date +%s.%N)
    runtime_ms=$(echo "scale=6; ($end - $start) * 1000" | bc)
    echo "BASH execution took $runtime_ms ms"
fi

source "$interactive_cache_extensions"

# Restore windows paths to PATH if running in WSL
export PATH="$PATH_CLEAN:$PATH_WINDOWS"

# Avoid error message after shell start
return 0
