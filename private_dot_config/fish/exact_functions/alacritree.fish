function alacritree --wraps='alacritree.exe'
    set -l bin $ALACRITREE_EXE
    if not set -q bin[1]
        set bin (command -s alacritree.exe)
    end
    if not set -q bin[1]
        echo "alacritree: alacritree.exe not found in PATH" >&2
        return 127
    end
    $bin $argv | cat
    return $pipestatus[1]
end
