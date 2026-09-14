# Dynamic value completions for the devkit CLIs.
#
# Layers on top of the `_generated.nu` in this directory, which
# `devkit completions --all nushell` writes: that covers subcommands, flags and
# enum values; these fill in the positional values clap can only know at runtime
# (tasks, apps, registered docs libs, worktrees, held locks, issue selectors).
#
# Nushell has no additive `complete` the way fish does, so every extern here is a
# whole redeclaration and the last one parsed wins. Autoload sources this
# directory in ASCII order, which is the only reason these beat the generated
# ones: a name sorting before `_generated.nu` silently loses. The flag lists are
# transcribed from the generated externs. Refresh them against
# `devkit completions --all nushell` whenever a devkit release moves a signature.
#
# Every command is declared twice: once under the split alias `devkit
# install-links` writes (`devrun task`) and once under the path through the
# single binary (`devkit run task`). Nushell keys an extern on its whole name,
# so the two spellings share nothing, and a machine that never ran
# `install-links` has only the second. The pairs differ by `--version`, which
# clap gives the subcommand but not the alias.

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

    # The values already typed after the subcommand, so a repeatable positional
    # (`devrun up api lab-os ...`) stops re-offering what it has. The command
    # path is dropped first: a registered library named `docs` would otherwise
    # read as a chosen value the moment `devkit docs sync` is on the line.
    def devkit-typed-values [context: string] {
        let words = (
            $context
            | split row -r '\s+'
            | where {|w| not ($w | str starts-with "-") }
        )
        let path = (if ($words | get -o 0 | default "") == "devkit" { 3 } else { 2 })
        $words | skip $path
    }

    def "nu-complete devkit apps rest" [context: string] {
        let used = (devkit-typed-values $context)
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
        devkit-json [devkit docs list --json]
        | default []
        | each {|d|
            let versions = ($d.checkouts | get worktree | str join ", ")
            { value: $d.name, description: $"($d.ecosystem): ($versions)" }
        }
    }

    def "nu-complete devkit docs rest" [context: string] {
        let used = (devkit-typed-values $context)
        nu-complete devkit docs | where {|d| $d.value not-in $used }
    }

    def "nu-complete devkit locked" [context: string] {
        let used = (devkit-typed-values $context)
        devkit-json [devkit locks status --all --json]
        | get -o locks
        | default []
        | each {|l| { value: $l.path, description: $"held by ($l.holder)" } }
        | where {|l| $l.value not-in $used }
    }

    def "nu-complete devkit holders" [] {
        devkit-json [devkit locks status --all --json]
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

    # devkit's own precedence: the `issue setup` record holds whatever the
    # tracker actually calls the issue, and the branch/directory scan is the
    # fallback for a worktree made by a plain `git worktree add`.
    def devkit-issue-id [worktree: string, branch: string] {
        let record = ([$worktree ".devkit" "issue.toml"] | path join)
        if ($record | path exists) {
            let recorded = (try { open $record | get -o issue } catch { null })
            if ($recorded | is-not-empty) { return $recorded }
        }
        # The leading class stands in for the lookbehind nushell's regex engine
        # does not have: it is devkit's "this letter run does not start
        # mid-word" test. A `pr-<number>` run is the PR-checkout marker rather
        # than an id, so it is dropped and the scan carries on.
        for source in [$branch ($worktree | path basename)] {
            let found = (
                $source
                | parse -r '(?:^|[^a-zA-Z])(?<key>[a-zA-Z]+)-(?<num>[0-9]+)'
                | where {|m| ($m.key | str lowercase) != "pr" }
                | get -o 0
            )
            if ($found | is-not-empty) {
                return ($"($found.key)-($found.num)" | str uppercase)
            }
        }
        ""
    }

    # Everything `issue end` accepts as a selector: the issue ids, branch names
    # and paths of this repository's issue worktrees. Offline on purpose, since
    # this runs on a keypress: it reads git and the record files rather than
    # calling `issue status`, which goes out to GitHub and the tracker.
    def "nu-complete devkit issue selectors" [context: string] {
        let used = (devkit-typed-values $context)
        let res = (^git worktree list --porcelain | complete)
        if $res.exit_code != 0 { return [] }
        $res.stdout
        | split row "\n\n"
        | where {|e| $e | str trim | is-not-empty }
        # git lists the primary checkout first, and it is never an issue worktree.
        | skip 1
        | each {|entry|
            let fields = ($entry | lines)
            let worktree = (
                $fields | where {|l| $l starts-with "worktree " } | get -o 0
                | default "" | str replace "worktree " ""
            )
            let branch = (
                $fields | where {|l| $l starts-with "branch " } | get -o 0
                | default "" | str replace -r '^branch refs/heads/' ''
            )
            { worktree: $worktree, branch: $branch }
        }
        | where {|w| $w.worktree | is-not-empty }
        # A baseline is not an issue worktree, and `end` never takes one.
        | where {|w| not ([$w.worktree ".devkit" "baseline.toml"] | path join | path exists) }
        | each {|w|
            let label = (if ($w.branch | is-empty) { $w.worktree | path basename } else { $w.branch })
            [
                { value: (devkit-issue-id $w.worktree $w.branch), description: $label }
                { value: $w.branch, description: ($w.worktree | path basename) }
                { value: $w.worktree, description: $label }
            ]
        }
        | flatten
        | where {|c| $c.value | is-not-empty }
        | where {|c| $c.value not-in $used }
    }

    def "nu-complete devkit timing" [] {
        [ "summary" "trace" ]
    }

    # Run a canned task from `[tasks]` (no name: list the configured tasks)
    export extern "devrun task" [
        --env: string             # Environment override applied to every step of the task. Repeatable
        --env-file: string        # Read K=V overrides from a file (blank lines and `#` comments skipped). A key also passed with --env wins
        --arg: string             # Set a template variable the task reads, over its `[templates.variables]` value. Repeatable
        --dry-run                 # Print the rendered plan (cwd, argv, env, resolved ports) without executing
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help
        name?: string@"nu-complete devkit tasks" # Task to run; omit to list the configured tasks
    ]
    # Run a canned task from `[tasks]` (no name: list the configured tasks)
    export extern "devkit run task" [
        --env: string             # Environment override applied to every step of the task. Repeatable
        --env-file: string        # Read K=V overrides from a file (blank lines and `#` comments skipped). A key also passed with --env wins
        --arg: string             # Set a template variable the task reads, over its `[templates.variables]` value. Repeatable
        --dry-run                 # Print the rendered plan (cwd, argv, env, resolved ports) without executing
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help
        --version(-V)             # Print version
        name?: string@"nu-complete devkit tasks" # Task to run; omit to list the configured tasks
    ]

    # Bring up dev servers for the selected apps
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
    # Bring up dev servers for the selected apps
    export extern "devkit run up" [
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
        --version(-V)             # Print version
        ...apps: string@"nu-complete devkit apps rest" # Apps to start; omit to infer them from the diff against the baseline ref. A fresh worktree has no diff yet, so name them there
    ]

    # Stop servers and release ports
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
    # Stop servers and release ports
    export extern "devkit run down" [
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
        --version(-V)             # Print version
        ...selectors: string@"nu-complete devkit apps rest" # Fuzzy selectors matched (substring) across columns. Mutually exclusive with the column filters below
    ]

    # Print (or follow) the log for one app
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
    # Print (or follow) the log for one app
    export extern "devkit run logs" [
        --role: string@"nu-complete devkit role" # Which side's log; omit to take whichever role is tracked
        --follow(-f)              # Follow the log instead of printing the last 200 lines
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help (see more with '--help')
        --version(-V)             # Print version
        app: string@"nu-complete devkit apps" # App whose log to read
    ]

    # Reserve a port per app for a holder (default: this worktree)
    export extern "portm alloc" [
        --holder: string@"nu-complete devkit worktrees" # Worktree root the ports belong to; defaults to the current worktree
        --role: string@"nu-complete devkit port role" # Role the reservation belongs to; issue and baseline get separate ports
        --help(-h)                # Print help
        ...apps: string@"nu-complete devkit apps rest" # Apps to reserve a port for, one row each
    ]
    # Reserve a port per app for a holder (default: this worktree)
    export extern "devkit ports alloc" [
        --holder: string@"nu-complete devkit worktrees" # Worktree root the ports belong to; defaults to the current worktree
        --role: string@"nu-complete devkit port role" # Role the reservation belongs to; issue and baseline get separate ports
        --help(-h)                # Print help
        --version(-V)             # Print version
        ...apps: string@"nu-complete devkit apps rest" # Apps to reserve a port for, one row each
    ]

    # Release a holder's reservations (default: this worktree)
    export extern "portm release" [
        --holder: string@"nu-complete devkit worktrees" # Worktree root whose ports to release; defaults to the current worktree
        --role: string@"nu-complete devkit port role" # Only this role; omit to release both
        --help(-h)                # Print help (see more with '--help')
        ...apps: string@"nu-complete devkit apps rest" # Only these apps; omit to release everything the holder has
    ]
    # Release a holder's reservations (default: this worktree)
    export extern "devkit ports release" [
        --holder: string@"nu-complete devkit worktrees" # Worktree root whose ports to release; defaults to the current worktree
        --role: string@"nu-complete devkit port role" # Only this role; omit to release both
        --help(-h)                # Print help (see more with '--help')
        --version(-V)             # Print version
        ...apps: string@"nu-complete devkit apps rest" # Only these apps; omit to release everything the holder has
    ]

    # Remove a library from the manifest (checkouts are reclaimed by prune)
    export extern "docm rm" [
        --project                 # Remove from the nearest devkit.toml [docs] section instead of the global manifest
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        name: string@"nu-complete devkit docs" # Registered library to drop
    ]
    # Remove a library from the manifest (checkouts are reclaimed by prune)
    export extern "devkit docs rm" [
        --project                 # Remove from the nearest devkit.toml [docs] section instead of the global manifest
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        --version(-V)             # Print version
        name: string@"nu-complete devkit docs" # Registered library to drop
    ]

    # Print the version-resolved checkout path (exactly one line on stdout)
    export extern "docm path" [
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        name: string@"nu-complete devkit docs" # Registered library to locate
    ]
    # Print the version-resolved checkout path (exactly one line on stdout)
    export extern "devkit docs path" [
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        --version(-V)             # Print version
        name: string@"nu-complete devkit docs" # Registered library to locate
    ]

    # Print checkout path, resolved version, layout map, and notes
    export extern "docm info" [
        --json                    # Emit the report as JSON instead of a table
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        name: string@"nu-complete devkit docs" # Registered library to describe
    ]
    # Print checkout path, resolved version, layout map, and notes
    export extern "devkit docs info" [
        --json                    # Emit the report as JSON instead of a table
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        --version(-V)             # Print version
        name: string@"nu-complete devkit docs" # Registered library to describe
    ]

    # Fetch, re-resolve, re-materialize and verify registered libraries
    export extern "docm sync" [
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        ...names: string@"nu-complete devkit docs rest" # Libraries to sync; omit for every registered library
    ]
    # Fetch, re-resolve, re-materialize and verify registered libraries
    export extern "devkit docs sync" [
        --allow-default-branch    # Check out the default branch when no tag or ref pins a version, instead of failing with a hard error
        --help(-h)                # Print help
        --version(-V)             # Print version
        ...names: string@"nu-complete devkit docs rest" # Libraries to sync; omit for every registered library
    ]

    # Claim one or more paths; fails if another session holds any
    export extern "lockm acquire" [
        --as: string@"nu-complete devkit holders" # Holder id. Defaults to the coding-agent session, then $DEVKIT_SESSION, $TMUX_PANE, the controlling tty, the parent pid
        --note: string            # Why you hold these paths; shown to whoever the claim blocks
        --ttl: string             # Lock lifetime, seconds (0 = no expiry). Default 1800 (30 min)
        --json                    # Emit the result as JSON instead of a human-readable line
        --help(-h)                # Print help (see more with '--help')
        ...paths: string          # Files or directories to claim
    ]
    # Claim one or more paths; fails if another session holds any
    export extern "devkit locks acquire" [
        --as: string@"nu-complete devkit holders" # Holder id. Defaults to the coding-agent session, then $DEVKIT_SESSION, $TMUX_PANE, the controlling tty, the parent pid
        --note: string            # Why you hold these paths; shown to whoever the claim blocks
        --ttl: string             # Lock lifetime, seconds (0 = no expiry). Default 1800 (30 min)
        --json                    # Emit the result as JSON instead of a human-readable line
        --help(-h)                # Print help (see more with '--help')
        --version(-V)             # Print version
        ...paths: string          # Files or directories to claim
    ]

    # Read-only: would `acquire` of these paths succeed?
    export extern "lockm check" [
        --as: string@"nu-complete devkit holders" # Holder id. Defaults to the coding-agent session, then $DEVKIT_SESSION, $TMUX_PANE, the controlling tty, the parent pid
        --json                    # Emit the result as JSON instead of a human-readable line
        --help(-h)                # Print help
        ...paths: string          # Files or directories to test
    ]
    # Read-only: would `acquire` of these paths succeed?
    export extern "devkit locks check" [
        --as: string@"nu-complete devkit holders" # Holder id. Defaults to the coding-agent session, then $DEVKIT_SESSION, $TMUX_PANE, the controlling tty, the parent pid
        --json                    # Emit the result as JSON instead of a human-readable line
        --help(-h)                # Print help
        --version(-V)             # Print version
        ...paths: string          # Files or directories to test
    ]

    # Release your claims on the named paths (or all of them with --all)
    export extern "lockm release" [
        --as: string@"nu-complete devkit holders" # Holder id. Defaults to the coding-agent session, then $DEVKIT_SESSION, $TMUX_PANE, the controlling tty, the parent pid
        --all                     # Release every path this holder claims
        --force                   # Release even a path held by another session
        --help(-h)                # Print help
        ...paths: string@"nu-complete devkit locked" # Paths to release; ignored with --all
    ]
    # Release your claims on the named paths (or all of them with --all)
    export extern "devkit locks release" [
        --as: string@"nu-complete devkit holders" # Holder id. Defaults to the coding-agent session, then $DEVKIT_SESSION, $TMUX_PANE, the controlling tty, the parent pid
        --all                     # Release every path this holder claims
        --force                   # Release even a path held by another session
        --help(-h)                # Print help
        --version(-V)             # Print version
        ...paths: string@"nu-complete devkit locked" # Paths to release; ignored with --all
    ]

    # Remove FINISHED worktrees (PR merged + issue done + clean)
    export extern "issue end" [
        --yes(-y)                 # Remove without asking for confirmation
        --force(-f)               # Discard uncommitted changes instead of refusing to remove a dirty worktree
        --pr-only(-p)             # Count a merged PR plus a clean tree as finished, ignoring the tracker state and the issue-id gate
        --clean-worktree(-w)      # Remove the selected worktrees whether or not they are finished. Requires at least one selector
        --no-preserve             # Remove without copying out the `[preserve]` entries first
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help
        ...ids: string@"nu-complete devkit issue selectors" # Issue ids, branches, or worktree paths to consider; omit to scan every issue worktree
    ]
    # Remove FINISHED worktrees (PR merged + issue done + clean)
    export extern "devkit issue end" [
        --yes(-y)                 # Remove without asking for confirmation
        --force(-f)               # Discard uncommitted changes instead of refusing to remove a dirty worktree
        --pr-only(-p)             # Count a merged PR plus a clean tree as finished, ignoring the tracker state and the issue-id gate
        --clean-worktree(-w)      # Remove the selected worktrees whether or not they are finished. Requires at least one selector
        --no-preserve             # Remove without copying out the `[preserve]` entries first
        --dir(-C): string         # Run as if this command had started in DIR instead of the current directory
        --config: string          # devkit.toml to load instead of the one discovered from the start directory
        --timing: string@"nu-complete devkit timing" # Print IO timing to stderr. `--timing` = summary, `--timing=trace` = per-op
        --timing-log: path        # Write one JSON record per timed IO op to FILE
        --help(-h)                # Print help
        --version(-V)             # Print version
        ...ids: string@"nu-complete devkit issue selectors" # Issue ids, branches, or worktree paths to consider; omit to scan every issue worktree
    ]
}

export use devkit_dynamic *
