# chezmoi:template:left-delimiter="# {{" right-delimiter="}}"
# {{- if .is_wsl -}}
# {{- if false -}}
# vim:filetype=bash.chezmoitmpl
# {{- end }}
if [[ ! -f "/tmp/wsl_init_finished" ]] || [[ -z "${SSH_AUTH_SOCK}" ]]; then
    ## SSH Sock
    if [[ -x "$HOME/go/bin/wsl2-ssh-agent" ]]; then
        export SSH_AUTH_SOCK="$HOME/.ssh/wsl2-ssh-agent.sock"
        if ! pidof wsl2-ssh-agent >/dev/null; then
            "$HOME/go/bin/wsl2-ssh-agent" >/dev/null
        fi
    elif [[ -x "$HOME/.ssh/wsl2-ssh-agent" ]]; then
        export SSH_AUTH_SOCK="$HOME/.ssh/wsl2-ssh-agent.sock"
        if ! pidof wsl2-ssh-agent >/dev/null; then
            "$HOME/.ssh/wsl2-ssh-agent" >/dev/null
        fi
    elif pidof wsl2-ssh-agent >/dev/null; then
        export SSH_AUTH_SOCK="$HOME/.ssh/wsl2-ssh-agent.sock"
    fi

    if [[ $(cat /proc/sys/fs/inotify/max_user_watches) -lt 524288 ]]; then
        #     sudo sysctl -p
        sudo sysctl fs.inotify.max_user_watches=524288
        sudo sysctl -p
    fi

    # Create socket file for xserver apps
    if [[ ! -e /tmp/.X11-unix ]]; then
        ln -s /mnt/wslg/.X11-unix /tmp/.X11-unix
    fi

    touch "/tmp/wsl_init_finshed"
fi
# {{- end }}
