function __fish_herdr_session_needs_agent
    set -l words (commandline -opc)
    set -l skip 0
    for word in $words[3..]
        if test $skip -eq 1
            set skip 0
            continue
        end
        switch $word
            case --path --session --label
                set skip 1
            case --
                return 1
            case '-*'
            case '*'
                return 1
        end
    end
    test $skip -eq 0
end

complete -c herdr-session -f
complete -c herdr-session -n 'not __fish_seen_subcommand_from open new list close' -a open -d 'Create or join this workspace'
complete -c herdr-session -n 'not __fish_seen_subcommand_from open new list close' -a new -d 'Open a new shell or agent tab'
complete -c herdr-session -n 'not __fish_seen_subcommand_from open new list close' -a list -d 'List sessions in this workspace'
complete -c herdr-session -n 'not __fish_seen_subcommand_from open new list close' -a close -d 'Close this workspace and its processes'
complete -c herdr-session -n 'not contains -- -- (commandline -opc)' -s h -l help -d 'Show help'
complete -c herdr-session -n 'not contains -- -- (commandline -opc)' -l session -r -d 'Use a named Herdr server session'
complete -c herdr-session -n 'not contains -- -- (commandline -opc)' -l path -r -a '(__fish_complete_directories)' -d 'Workspace directory'
complete -c herdr-session -n 'not contains -- -- (commandline -opc)' -l label -r -d 'Name for a new workspace'
complete -c herdr-session -n '__fish_seen_subcommand_from list' -l json -d 'Print session rows as JSON'
complete -c herdr-session -n '__fish_seen_subcommand_from new; and not contains -- -- (commandline -opc)' -l list-agents -d 'Print installed agent choices'
complete -c herdr-session -n '__fish_seen_subcommand_from new; and __fish_herdr_session_needs_agent' -a '(herdr-session new --list-agents)' -d 'Start this coding agent'
complete -c herdr-session -n '__fish_seen_subcommand_from new; and __fish_herdr_session_needs_agent' -a shell -d 'Open a shell tab'
