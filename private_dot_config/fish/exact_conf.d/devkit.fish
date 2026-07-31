# Dynamic value completions for the devkit CLIs.
#
# Layers on top of the static `<bin> completions fish` scripts: those already
# cover subcommands, flags and enum values; these fill in the positional values
# clap can only know at runtime (tasks, apps, registered docs libs, worktrees,
# held locks). Independent of load order — a `-f` entry suppresses the static
# script's filename fallback for the same option.
#
# Requires: jq.

function __devkit_tasks
    devrun config tasks --json 2>/dev/null |
        jq -r '.[] | "\(.name)\t\(.kind): \(.description)"'
end

function __devkit_task_names
    devrun config tasks --json 2>/dev/null | jq -r '.[].name'
end

function __devkit_apps
    devrun config apps --json 2>/dev/null |
        jq -r '.[] | "\(.name)\t\(.path)"'
end

function __devkit_app_names
    devrun config apps --json 2>/dev/null | jq -r '.[].name'
end

function __devkit_docs_libs
    docm list --json 2>/dev/null |
        jq -r '.[] | "\(.name)\t\(.ecosystem): \(.synced | join(", "))"'
end

function __devkit_docs_names
    docm list --json 2>/dev/null | jq -r '.[].name'
end

function __devkit_worktrees
    git worktree list --porcelain 2>/dev/null | string match -rg '^worktree (.+)'
end

function __devkit_locked_paths
    lockm status --all --json 2>/dev/null |
        jq -r '.locks[] | "\(.path)\theld by \(.holder)"'
end

function __devkit_lock_holders
    lockm status --all --json 2>/dev/null | jq -r '.locks[].holder' | sort -u
end

# Drop candidates already present on the command line, so a repeatable
# positional (`devrun up api lab-os …`) stops re-offering what it has.
function __devkit_unused
    set -l used (commandline -opc)
    while read -l line
        contains -- (string split -f1 \t -- $line) $used; or echo $line
    end
end

# True when one of $argv is already on the command line — used to stop
# re-offering values for a positional that takes exactly one.
function __devkit_chosen_from
    for token in (commandline -opc)
        contains -- $token $argv; and return 0
    end
    return 1
end

### devrun

complete -c devrun -f -n '__fish_seen_subcommand_from task; and not __devkit_chosen_from (__devkit_task_names)' \
    -a '(__devkit_tasks)'
# Suppress fish's filename fallback once the single positional is filled;
# `--env-file` keeps its own file completion, and flags still complete.
complete -c devrun -f -n '__fish_seen_subcommand_from task; and __devkit_chosen_from (__devkit_task_names)'

complete -c devrun -f -n '__fish_seen_subcommand_from up' -a '(__devkit_apps | __devkit_unused)'
complete -c devrun -f -n '__fish_seen_subcommand_from logs; and not __devkit_chosen_from (__devkit_app_names)' \
    -a '(__devkit_apps)'
complete -c devrun -f -n '__fish_seen_subcommand_from logs; and __devkit_chosen_from (__devkit_app_names)'
complete -c devrun -f -n '__fish_seen_subcommand_from down' -a '(__devkit_apps | __devkit_unused)'
complete -c devrun -f -n '__fish_seen_subcommand_from down' -l app -r -a '(__devkit_apps)'
complete -c devrun -f -n '__fish_seen_subcommand_from down' -l holder -r -a '(__devkit_worktrees)'

### portm

complete -c portm -f -n '__fish_seen_subcommand_from alloc reserve release' \
    -a '(__devkit_apps | __devkit_unused)'
complete -c portm -f -n '__fish_seen_subcommand_from alloc reserve release' \
    -l holder -r -a '(__devkit_worktrees)'

### docm

complete -c docm -f -n '__fish_seen_subcommand_from rm path info; and not __devkit_chosen_from (__devkit_docs_names)' \
    -a '(__devkit_docs_libs)'
complete -c docm -f -n '__fish_seen_subcommand_from rm path info; and __devkit_chosen_from (__devkit_docs_names)'
complete -c docm -f -n '__fish_seen_subcommand_from sync' -a '(__devkit_docs_libs | __devkit_unused)'

### lockm

complete -c lockm -f -n '__fish_seen_subcommand_from release' \
    -a '(__devkit_locked_paths | __devkit_unused)'
complete -c lockm -f -n '__fish_seen_subcommand_from acquire check release status' \
    -l as -r -a '(__devkit_lock_holders)'
