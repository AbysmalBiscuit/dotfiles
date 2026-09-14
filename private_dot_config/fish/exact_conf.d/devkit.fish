# Dynamic value completions for the devkit CLIs.
#
# Layers on top of the static `<bin> completions fish` scripts: those already
# cover subcommands, flags and enum values; these fill in the positional values
# clap can only know at runtime (tasks, apps, registered docs libs, worktrees,
# held locks). Independent of load order: a `-f` entry suppresses the static
# script's filename fallback for the same option.
#
# Every rule is registered twice, once for the split alias `devkit install-links`
# writes (`devrun task`) and once for the path through the single binary
# (`devkit run task`), so a machine that never ran `install-links` still gets
# them. The two differ only in the subcommand words, so the loops below carry
# that difference in `$pfx` and state each rule once.
#
# Requires: jq.

function __devkit_tasks
    devkit config tasks --json 2>/dev/null |
        jq -r '.[] | "\(.name)\t\(.kind): \(.description)"'
end

function __devkit_task_names
    devkit config tasks --json 2>/dev/null | jq -r '.[].name'
end

function __devkit_apps
    devkit config apps --json 2>/dev/null |
        jq -r '.[] | "\(.name)\t\(.path)"'
end

function __devkit_app_names
    devkit config apps --json 2>/dev/null | jq -r '.[].name'
end

function __devkit_docs_libs
    devkit docs list --json 2>/dev/null |
        jq -r '.[] | "\(.name)\t\(.ecosystem): \(.checkouts | map(.worktree) | join(", "))"'
end

function __devkit_docs_names
    devkit docs list --json 2>/dev/null | jq -r '.[].name'
end

function __devkit_worktrees
    git worktree list --porcelain 2>/dev/null | string match -rg '^worktree (.+)'
end

function __devkit_locked_paths
    devkit locks status --all --json 2>/dev/null |
        jq -r '.locks[] | "\(.path)\theld by \(.holder)"'
end

function __devkit_lock_holders
    devkit locks status --all --json 2>/dev/null | jq -r '.locks[].holder' | sort -u
end

# True when $argv appears in order among the words after the binary. Ordered
# rather than positional so a global flag and its value (`devkit -C dir run`)
# does not shift the match off the subcommand.
function __devkit_subcommand
    set -l want $argv
    for token in (commandline -opc)[2..]
        test "$token" = "$want[1]"; and set -e want[1]
        test (count $want) -eq 0; and return 0
    end
    return 1
end

# The values already typed after the subcommand $leaf. Scanning the whole line
# instead would read a command word as a value: a registered library is named
# `docs`, so `devkit docs rm` would look like it already has its argument.
function __devkit_values --argument-names leaf
    set -l tokens (commandline -opc)
    set -l idx (contains -i -- $leaf $tokens)
    test -n "$idx"; or return
    set -e tokens[1..$idx]
    for token in $tokens
        string match -q -- '-*' $token; or echo $token
    end
end

# Drop candidates already given, so a repeatable positional
# (`devrun up api lab-os ...`) stops re-offering what it has.
function __devkit_unused --argument-names leaf
    set -l used (__devkit_values $leaf)
    while read -l line
        contains -- (string split -f1 \t -- $line) $used; or echo $line
    end
end

# True when a positional that takes exactly one value already has it.
function __devkit_chosen --argument-names leaf
    for value in (__devkit_values $leaf)
        contains -- $value $argv[2..]; and return 0
    end
    return 1
end

### devrun | devkit run

for cmd in devrun devkit
    set -l pfx
    test $cmd = devkit; and set pfx run

    complete -c $cmd -f \
        -n "__devkit_subcommand $pfx task; and not __devkit_chosen task (__devkit_task_names)" \
        -a '(__devkit_tasks)'
    # Suppress fish's filename fallback once the single positional is filled;
    # `--env-file` keeps its own file completion, and flags still complete.
    complete -c $cmd -f \
        -n "__devkit_subcommand $pfx task; and __devkit_chosen task (__devkit_task_names)"

    complete -c $cmd -f -n "__devkit_subcommand $pfx up" -a '(__devkit_apps | __devkit_unused up)'

    complete -c $cmd -f \
        -n "__devkit_subcommand $pfx logs; and not __devkit_chosen logs (__devkit_app_names)" \
        -a '(__devkit_apps)'
    complete -c $cmd -f \
        -n "__devkit_subcommand $pfx logs; and __devkit_chosen logs (__devkit_app_names)"

    complete -c $cmd -f -n "__devkit_subcommand $pfx down" -a '(__devkit_apps | __devkit_unused down)'
    complete -c $cmd -f -n "__devkit_subcommand $pfx down" -l app -r -a '(__devkit_apps)'
    complete -c $cmd -f -n "__devkit_subcommand $pfx down" -l holder -r -a '(__devkit_worktrees)'
end

### portm | devkit ports

for cmd in portm devkit
    set -l pfx
    test $cmd = devkit; and set pfx ports

    for sub in alloc release
        complete -c $cmd -f -n "__devkit_subcommand $pfx $sub" \
            -a "(__devkit_apps | __devkit_unused $sub)"
        complete -c $cmd -f -n "__devkit_subcommand $pfx $sub" \
            -l holder -r -a '(__devkit_worktrees)'
    end
end

### docm | devkit docs

for cmd in docm devkit
    set -l pfx
    test $cmd = devkit; and set pfx docs

    for sub in rm path info
        complete -c $cmd -f \
            -n "__devkit_subcommand $pfx $sub; and not __devkit_chosen $sub (__devkit_docs_names)" \
            -a '(__devkit_docs_libs)'
        complete -c $cmd -f \
            -n "__devkit_subcommand $pfx $sub; and __devkit_chosen $sub (__devkit_docs_names)"
    end

    complete -c $cmd -f -n "__devkit_subcommand $pfx sync" \
        -a '(__devkit_docs_libs | __devkit_unused sync)'
end

### lockm | devkit locks

for cmd in lockm devkit
    set -l pfx
    test $cmd = devkit; and set pfx locks

    complete -c $cmd -f -n "__devkit_subcommand $pfx release" \
        -a '(__devkit_locked_paths | __devkit_unused release)'

    for sub in acquire check release
        complete -c $cmd -f -n "__devkit_subcommand $pfx $sub" \
            -l as -r -a '(__devkit_lock_holders)'
    end
end
