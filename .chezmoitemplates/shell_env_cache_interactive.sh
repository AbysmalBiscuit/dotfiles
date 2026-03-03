# Starting fish shell, and make sure to exit after
if [[ -x $(command -v fish 2>/dev/null) && -z "$BASH_EXECUTION_STRING" && "$FORCEBASH" != "1" ]]; then
    if [[ "$debug_shell_startup" = "true" ]]; then
        end=$(date +%s.%N)
        runtime_ms=$(echo "scale=6; ($end - $start) * 1000" | bc)
        echo "BASH execution took $runtime_ms ms"
    fi

    exec fish
fi

# if grep -qv 'fish' /proc/$PPID/comm && [[ ${SHLVL} == [1,2] && "$FORCEBASH" != "1" ]]; then
#     shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=''
#     echo $LOGIN_OPTION
#     exec fish $LOGIN_OPTION
# fi

if [[ "$debug_shell_startup" = "true" ]]; then
    end=$(date +%s.%N)
    runtime_ms=$(echo "scale=6; ($end - $start) * 1000" | bc)
    echo "BASH execution took $runtime_ms ms"
fi

source "$interactive_cache_extensions"

{{- if .system.is_wsl }}

# Restore windows paths to PATH if running in WSL
export PATH="$PATH_CLEAN:$PATH_WINDOWS"
{{- end }}

# Avoid error message after shell start
return 0
