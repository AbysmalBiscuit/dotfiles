# Dynamic value completions for the devkit CLIs.
#
# Layers on top of the `_generated.nu` in this directory, which
# `devkit completions --all nushell` writes: that covers subcommands, flags and
# enum values; these fill in the positional values clap can only know at runtime
# (tasks, apps, registered docs libs, worktrees, held locks).
#
# Nushell has no additive `complete` the way fish does, so every extern here is a
# whole redeclaration and the last one parsed wins. Autoload sources this
# directory in ASCII order, which is the only reason these beat the generated
# ones: a name sorting before `_generated.nu` silently loses. The flag lists are
# transcribed from the generated externs — refresh them against
# `devkit completions --all nushell` whenever a devkit release moves a signature.

module devkit_dynamic {
    # Nothing rather than an error when the binary is absent or the call fails,
    # so a keypress on a machine without devkit falls back to file completion
    # instead of painting a stack trace over the prompt.
    def devkit-json [argv: list<string>] {
        if (which ($argv | first) | is-empty) { return null }
        let res = (run-external ...$argv | complete)
        if $res.exit_code != 0 { return null }
        try { $res.stdout | from json } catch { null }
    }

    def "nu-complete devkit tasks" [] {
        devkit-json [devkit config tasks --json]
        | default []
        | each {|t| { value: $t.name, description: $"($t.kind): ($t.description)" } }
    }

    def "nu-complete devkit apps" [] {
        devkit-json [devkit config apps --json]
        | default []
        | each {|a| { value: $a.name, description: $a.path } }
    }

    # Drop candidates already on the command line, so a repeatable positional
    # (`devrun up api lab-os …`) stops re-offering what it has.
    def "nu-complete devkit apps rest" [context: string] {
        let used = ($context | split row -r '\s+')
        nu-complete devkit apps | where {|a| $a.value not-in $used }
    }

    def "nu-complete devkit worktrees" [] {
        let res = (^git worktree list --porcelain | complete)
        if $res.exit_code != 0 { return [] }
        $res.stdout
        | lines
        | where {|l| $l starts-with "worktree " }
        | each {|l| $l | str replace -r '^worktree ' '' }
    }

    def "nu-complete devkit docs" [] {
        devkit-json [docm list --json]
        | default []
        | each {|d|
            let versions = ($d.checkouts | get worktree | str join ", ")
            { value: $d.name, description: $"($d.ecosystem): ($versions)" }
        }
    }

    def "nu-complete devkit docs rest" [context: string] {
        let used = ($context | split row -r '\s+')
        nu-complete devkit docs | where {|d| $d.value not-in $used }
    }

    def "nu-complete devkit locked" [context: string] {
        let used = ($context | split row -r '\s+')
        devkit-json [lockm status --all --json]
        | get -o locks
        | default []
        | each {|l| { value: $l.path, description: $"held by ($l.holder)" } }
        | where {|l| $l.value not-in $used }
    }

    def "nu-complete devkit holders" [] {
        devkit-json [lockm status --all --json]
        | get -o locks
        | default []
        | get holder
        | uniq
        | sort
    }

    def "nu-complete devkit role" [] {
        [ "issue" "baseline" "both" ]
    }

    def "nu-complete devkit port role" [] {
        [ "issue" "baseline" ]
    }

    def "nu-complete devkit timing" [] {
        [ "summary" "trace" ]
    }

    export extern "devrun task" [
        --env: string             # Environment override applied to every step of the task. Repeatable
        --env-file: string        # Read K=V overrides from a file (blank lines and `#` comments skipped). A key also passed with --env wins
        --dry-run                 # Print the rendered plan (cwd, argv, env, resolved ports) without executing
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help
        name?: string@"nu-complete devkit tasks" # Task to run; omit to list the configured tasks
    ]

    export extern "devrun up" [
        --role: string@"nu-complete devkit role" # Which side to run
        --env: string             # Environment override for the launched servers, above the app's `static_env`. Repeatable
        --env-file: string        # Read K=V overrides from a file (blank lines and `#` comments skipped). A key also passed with --env wins
        --dry-run                 # Print the launch plan without starting anything
        --supervise               # Hand servers to the supervisor daemon (autostarting it) so they restart on crash
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help (see more with '--help')
        ...apps: string@"nu-complete devkit apps rest" # Apps to start; omit to infer them from the diff against the baseline ref. A fresh worktree has no diff yet, so name them there
    ]

    export extern "devrun down" [
        --all                     # Every holder, including this worktree
        --others                  # Every holder except this worktree
        --holder: string@"nu-complete devkit worktrees" # One specific worktree (repeatable), by path
        --batch                   # Collapse cross-worktree confirmation into one combined prompt
        --app: string@"nu-complete devkit apps" # Filter: app name (repeatable)
        --port: string            # Filter: port (repeatable)
        --role: string@"nu-complete devkit role" # Filter: role
        --pid: string             # Filter: pid
        --listening               # Filter: only servers currently listening
        --not-listening           # Filter: only servers not currently listening
        --older-than: string      # Filter: only servers older than this (90s, 30m, 2h, 1d)
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help (see more with '--help')
        ...selectors: string@"nu-complete devkit apps rest" # Fuzzy selectors matched (substring) across columns. Mutually exclusive with the column filters below
    ]

    export extern "devrun logs" [
        --role: string@"nu-complete devkit role" # Which side's log; omit to take whichever role is tracked
        --follow(-f)              # Follow the log instead of printing the last 200 lines
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help (see more with '--help')
        app: string@"nu-complete devkit apps" # App whose log to read
    ]

    export extern "portm alloc" [
        --holder: string@"nu-complete devkit worktrees" # Worktree root the ports belong to; defaults to the current worktree
        --role: string@"nu-complete devkit port role" # Role the reservation belongs to; issue and baseline get separate ports
        --help(-h)                # Print help
        ...apps: string@"nu-complete devkit apps rest" # Apps to reserve a port for, one row each
    ]

    export extern "portm release" [
        --holder: string@"nu-complete devkit worktrees" # Worktree root whose ports to release; defaults to the current worktree
        --role: string@"nu-complete devkit port role" # Only this role; omit to release both
        --help(-h)                # Print help (see more with '--help')
        ...apps: string@"nu-complete devkit apps rest" # Only these apps; omit to release everything the holder has
    ]

    export extern "docm rm" [
        --project                 # Remove from the nearest devkit.toml [docs] section instead of the global manifest
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        name: string@"nu-complete devkit docs" # Registered library to drop
    ]

    export extern "docm path" [
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        name: string@"nu-complete devkit docs" # Registered library to locate
    ]

    export extern "docm info" [
        --json                    # Emit the report as JSON instead of a table
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        name: string@"nu-complete devkit docs" # Registered library to describe
    ]

    export extern "docm sync" [
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        ...names: string@"nu-complete devkit docs rest" # Libraries to sync; omit for every registered library
    ]

    export extern "lockm release" [
        --as: string@"nu-complete devkit holders" # Session identity to hold the claim under. Defaults to $DEVKIT_SESSION, then $TMUX_PANE, then the controlling tty, then the parent pid. Pass the same value to acquire and release
        --all                     # Release every path this holder claims
        --force                   # Release even a path held by another session
        --help(-h)                # Print help
        ...paths: string@"nu-complete devkit locked" # Paths to release; ignored with --all
    ]

    export extern "lockm acquire" [
        --as: string@"nu-complete devkit holders" # Session identity to hold the claim under. Defaults to $DEVKIT_SESSION, then $TMUX_PANE, then the controlling tty, then the parent pid. Pass the same value to acquire and release
        --note: string            # Why you hold these paths; shown to whoever the claim blocks
        --ttl: string             # Lock lifetime, seconds (0 = no expiry). Default 1800 (30 min)
        --json                    # Emit the result as JSON instead of a human-readable line
        --help(-h)                # Print help (see more with '--help')
        ...paths: string          # Files or directories to claim
    ]

    export extern "lockm check" [
        --as: string@"nu-complete devkit holders" # Session identity to hold the claim under. Defaults to $DEVKIT_SESSION, then $TMUX_PANE, then the controlling tty, then the parent pid. Pass the same value to acquire and release
        --json                    # Emit the result as JSON instead of a human-readable line
        --help(-h)                # Print help
        ...paths: string          # Files or directories to test
    ]
}

export use devkit_dynamic *
