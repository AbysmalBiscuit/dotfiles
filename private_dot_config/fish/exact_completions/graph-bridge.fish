# graph-bridge — cross-app link enrichment for the adaptyv monorepo graph.
# Subcommands and flags mirror bridge/cli.py.

set -l gb_cmds link report build label update audit claude hook-guard

function __graph_bridge_no_subcommand
    not __fish_seen_subcommand_from link report build label update audit claude hook-guard
end

function __graph_bridge_providers
    # Names accepted by --provider: entries under [labels.providers.*] in the
    # per-machine TOML, plus graphify's own backends, which are usable bare.
    set -l base $XDG_CONFIG_HOME
    test -n "$base"; or set base $HOME/.config
    set -l cfg $base/graph-bridge/config.toml
    if test -f $cfg
        string replace -rf '^\s*\[labels\.providers\.([^]]+)\]\s*$' '$1' <$cfg
    end
    printf '%s\n' azure bedrock claude claude-cli deepseek gemini kimi ollama openai
end

# No bare-word arguments anywhere; every value arrives behind a flag.
complete -c graph-bridge -f

complete -c graph-bridge -n __graph_bridge_no_subcommand -a update \
    -d 'Refresh the graph: extract changes, relabel, relink'
complete -c graph-bridge -n __graph_bridge_no_subcommand -a build \
    -d 'Full rebuild, re-introspecting the Postgres schema'
complete -c graph-bridge -n __graph_bridge_no_subcommand -a label \
    -d 'Name communities with an LLM, without re-extracting'
complete -c graph-bridge -n __graph_bridge_no_subcommand -a link \
    -d 'Write cross-boundary edges into an existing graph'
complete -c graph-bridge -n __graph_bridge_no_subcommand -a report \
    -d 'Print what link would write, changing nothing'
complete -c graph-bridge -n __graph_bridge_no_subcommand -a audit \
    -d "Score graphify's pick for every ambiguous call target"
complete -c graph-bridge -n __graph_bridge_no_subcommand -a claude \
    -d 'Install or remove the bare-graphify rebuild guard'
complete -c graph-bridge -n __graph_bridge_no_subcommand -a hook-guard \
    -d 'PreToolUse hook entry point (not run by hand)'

# --root and --config are accepted by every subcommand except hook-guard.
complete -c graph-bridge -n '__fish_seen_subcommand_from link report build label update audit claude' \
    -l root -r -F -d 'Extraction root (default: git toplevel of cwd)'
complete -c graph-bridge -n '__fish_seen_subcommand_from link report build label update audit claude' \
    -l config -r -F -d 'graph-bridge config (default: bundled adaptyv.yaml)'

complete -c graph-bridge -n '__fish_seen_subcommand_from link report audit' \
    -l graph -r -F -d 'graph.json (default: <root>/<GRAPHIFY_OUT>/graph.json)'

complete -c graph-bridge -n '__fish_seen_subcommand_from build label update' \
    -l provider -x -a '(__graph_bridge_providers)' \
    -d 'Labeling provider: a configured name or a bare backend'

complete -c graph-bridge -n '__fish_seen_subcommand_from build' \
    -l postgres -x -d 'LOCAL dev DB DSN; overrides the config'
complete -c graph-bridge -n '__fish_seen_subcommand_from build update' \
    -l no-postgres -d 'Skip schema introspection even with postgres.dsn set'

complete -c graph-bridge -n '__fish_seen_subcommand_from update' \
    -l force -d 'Rebuild from scratch, re-introspecting and overwriting'

complete -c graph-bridge -n '__fish_seen_subcommand_from label' \
    -l all -d 'Label every community, bypassing max_drifted'

complete -c graph-bridge -n '__fish_seen_subcommand_from audit' \
    -l limit -x -d 'Score a random sample of N edges instead of all'
complete -c graph-bridge -n '__fish_seen_subcommand_from audit' \
    -l seed -x -d 'Sample seed (default 0)'
complete -c graph-bridge -n '__fish_seen_subcommand_from audit' \
    -l out -r -F -d 'Prefix for the <out>-rows.jsonl dump'

function __graph_bridge_bare_claude
    # `claude` is a --provider value as well as a subcommand, and
    # __fish_seen_subcommand_from cannot tell a flag's value from a subcommand.
    # The subcommand only ever sits at position 2.
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 2; and test "$tokens[2]" = claude
end

complete -c graph-bridge -n __graph_bridge_bare_claude \
    -a install -d 'Install the guard into this repo'
complete -c graph-bridge -n __graph_bridge_bare_claude \
    -a uninstall -d 'Remove the guard from this repo'
complete -c graph-bridge -n __graph_bridge_bare_claude \
    -a status -d 'Report whether the guard is installed'
