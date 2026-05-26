if type -q wslinfo
    function neovide --wraps='neovide' --description 'alias neovide="neovide.exe --wsl"'
        set neovide_exe (command -v neovide.exe)
        $neovide_exe --wsl $argv
    end
end
