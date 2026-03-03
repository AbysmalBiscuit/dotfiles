{{ if .system.is_wsl -}}
## SSH Sock
if has_command wsl2-ssh-agent; then
    export SSH_AUTH_SOCK="$HOME/.ssh/wsl2-ssh-agent.sock"
    if ! pidof wsl2-ssh-agent >/dev/null; then
        wsl2-ssh-agent
    fi
elif has_command "$HOME/.ssh/wsl2-ssh-agent"; then
    export SSH_AUTH_SOCK="$HOME/.ssh/wsl2-ssh-agent.sock"
    if ! pidof wsl2-ssh-agent >/dev/null; then
        "$HOME/.ssh/wsl2-ssh-agent"
    fi
fi

if [[ $(cat /proc/sys/fs/inotify/max_user_watches) -lt 524288 ]]; then
    #     sudo sysctl -p
    sudo sysctl fs.inotify.max_user_watches=524288
    sudo sysctl -p
fi

# Create socket file for xserver apps
if [ ! -e /tmp/.X11-unix ]; then
    ln -s /mnt/wslg/.X11-unix /tmp/.X11-unix
fi
{{- end }}
