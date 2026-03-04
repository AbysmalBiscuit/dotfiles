{{ if .system.is_linux -}}
export IBUS_ENABLE_SYNC_MODE=1
{{- end }}
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
for d in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
    if [[ ! -d "$d" ]]; then
        mkdir -p "$d"
    fi
done

export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=C.UTF-8
export LC_NUMERIC=fr_CH.UTF-8
export LC_TIME=en_DK.UTF-8
export LC_COLLATE=C.UTF-8
export LC_MONETARY=fr_CH.UTF-8
export LC_MESSAGES=en_US.UTF-8
export LC_PAPER=fr_CH.UTF-8
export LC_NAME=en_US.UTF-8
export LC_ADDRESS=fr_CH.UTF-8
export LC_TELEPHONE=fr_CH.UTF-8
export LC_MEASUREMENT=fr_CH.UTF-8
export LC_IDENTIFICATION=fr_CH.UTF-8
