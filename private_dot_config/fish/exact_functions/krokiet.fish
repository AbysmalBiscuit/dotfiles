function krokiet --description 'Convenience wrapper for krokiet'
    set -l dir_
    if set -q argv[1]
        for path in $argv
            set -a dir_ (wslpath -w $path)
        end
    else
        set dir_ (pwd)
    end

    switch $OS
        case wsl
            env PATH="$PATH_WINDOWS" krokiet.exe $dir_
            return 0
        case darwin*
            krokiet $dir_
            return 0
        case linux*
            krokiet $dir_
            return 0
        case '*'
            echo "No file explorer known for '$OS'"
            return 1
    end
end
