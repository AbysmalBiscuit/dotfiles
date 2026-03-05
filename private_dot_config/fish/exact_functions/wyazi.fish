function wyazi --wraps yazi --description 'alias yazi=yazi; uses windows yazi on wsl on windows disks if it\'s available'
    if test $OS = wsl; and string match -q '/mnt/*' "$PWD"; and set -q YAZI_WINDOWS_EXECUTABLE[1]
        $YAZI_WINDOWS_EXECUTABLE $argv
    else
        command yazi $argv
    end
end
