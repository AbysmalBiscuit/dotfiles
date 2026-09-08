function herdr --description 'Herdr with sn as a shortcut for herdr-session'
    if test "$argv[1]" = sn
        command herdr-session $argv[2..]
    else
        command herdr $argv
    end
end
