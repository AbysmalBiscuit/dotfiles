if [[ "$debug_shell_startup" = "true" ]]; then
    end=$(date +%s.%N)
    runtime_ms=$(echo "scale=6; ($end - $start) * 1000" | bc)
    echo "startup execution took $runtime_ms ms"
fi
