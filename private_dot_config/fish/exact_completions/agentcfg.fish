# agentcfg — merge strategies for the keys the agent configs write themselves.
# The path list comes from `agentcfg complete`, which reads the same baseline
# and live files `remove` writes to, so a tab never offers a key that is gone.

function __agentcfg_no_subcommand
    not __fish_seen_subcommand_from remove complete
end

complete -c agentcfg -f

# Answered at every depth, so this rule names no subcommand.
complete -c agentcfg -s h -l help -d 'Show usage and exit'

complete -c agentcfg -n __agentcfg_no_subcommand -a remove \
    -d 'Clear a key from the baseline, the live file and the app'
complete -c agentcfg -n __agentcfg_no_subcommand -l list \
    -d 'Print the drift candidates and exit'

complete -c agentcfg -n '__fish_seen_subcommand_from remove' -l dry-run \
    -d 'Print the plan and write nothing'
complete -c agentcfg -n '__fish_seen_subcommand_from remove' -l keep-installed \
    -d "Edit the configs, leave the app's own files alone"

# `--` guards the token: a half-typed flag would otherwise read as a prefix.
complete -c agentcfg -n '__fish_seen_subcommand_from remove' \
    -a '(agentcfg complete -- (commandline --current-token))'
