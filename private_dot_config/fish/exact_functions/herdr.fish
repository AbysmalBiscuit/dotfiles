function herdr --description 'Herdr with sn and restart as shortcuts for the helper commands'
    switch "$argv[1]"
        case sn
            command herdr-session $argv[2..]
        case restart
            command herdr-restart $argv[2..]
        case '*'
            command herdr $argv
    end
end
