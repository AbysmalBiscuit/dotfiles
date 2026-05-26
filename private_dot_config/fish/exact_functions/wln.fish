function wln --description 'create windows system links'
    argparse s/symbolic -- $argv
    or return

    if test $argv[1] = -s
        set symlink true
        set from (wslpath -w "$argv[2]")
        set to (wslpath -w "$argv[3]")
    else
        set symlink false
        set from (wslpath -w "$argv[1]")
        set to (wslpath -w "$argv[2]")
    end

    if $symlink
        if test -d "$from"
            cmd.exe /C "mklink /D $to $from"
        else
            cmd.exe /C "mklink $to $from"
        end
    else
        set win_home (wslpath -u (wslvar USERPROFILE))

        set ps_script ""(wslpath -w "$win_home/bin/wln.ps1")

        if string match -r -q --invert '\.(lnk|url)$' "$to"
            set to "$to.lnk"
        end

        powershell.exe "$ps_script" "$from" "$to"
    end
end
