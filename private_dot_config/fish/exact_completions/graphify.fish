# graphify — code/doc knowledge graphs.
# graphify parses argv by hand rather than with argparse, so this file follows
# `graphify --help` and the dispatch table in graphify/cli.py.

set -l gf_platforms claude windows codebuddy codex opencode aider amp agents claw droid trae trae-cn gemini cursor antigravity hermes kiro pi devin
set -l gf_editors gemini cursor claude codebuddy codex opencode kilo aider copilot vscode claw droid trae trae-cn antigravity hermes kiro pi devin
set -l gf_cmds install uninstall path explain diagnose clone merge-driver merge-graphs \
    add watch update cluster-only label query affected god-nodes save-result reflect \
    check-update tree extract global benchmark export hook provider prs hook-check \
    hook-guard cache-check merge-chunks merge-semantic $gf_editors

function __graphify_no_subcommand -V gf_cmds
    not __fish_seen_subcommand_from $gf_cmds
end

function __graphify_bare_command
    # The command word sits at position 2 and nowhere else. Several of these
    # names — claude, gemini, codex — are also --backend and --platform values,
    # and __fish_seen_subcommand_from cannot tell a flag's value from a command,
    # so it offers `install` after `--backend claude`.
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 2; and contains -- $tokens[2] $argv
end

complete -c graphify -f

# --- top-level commands ------------------------------------------------------

complete -c graphify -n __graphify_no_subcommand -a extract \
    -d 'Headless full extraction (AST + semantic LLM)'
complete -c graphify -n __graphify_no_subcommand -a update \
    -d 'Re-extract code files and update the graph (no LLM)'
complete -c graphify -n __graphify_no_subcommand -a watch \
    -d 'Watch a folder and rebuild on code changes'
complete -c graphify -n __graphify_no_subcommand -a query \
    -d 'BFS traversal of graph.json for a question'
complete -c graphify -n __graphify_no_subcommand -a explain \
    -d 'Plain-language explanation of a node and its neighbors'
complete -c graphify -n __graphify_no_subcommand -a path \
    -d 'Shortest path between two nodes'
complete -c graphify -n __graphify_no_subcommand -a affected \
    -d 'Reverse traversal: what is impacted by a node'
complete -c graphify -n __graphify_no_subcommand -a god-nodes \
    -d 'List the most connected nodes (architectural hubs)'
complete -c graphify -n __graphify_no_subcommand -a label \
    -d 'Rename communities with the configured LLM backend'
complete -c graphify -n __graphify_no_subcommand -a cluster-only \
    -d 'Rerun clustering on an existing graph.json'
complete -c graphify -n __graphify_no_subcommand -a save-result \
    -d 'Save a Q&A result to the work-memory corpus'
complete -c graphify -n __graphify_no_subcommand -a reflect \
    -d 'Aggregate memory outcomes into LESSONS.md'
complete -c graphify -n __graphify_no_subcommand -a diagnose \
    -d 'Report same-endpoint edge collapse risk'
complete -c graphify -n __graphify_no_subcommand -a tree \
    -d 'Emit a collapsible-tree HTML for graph.json'
complete -c graphify -n __graphify_no_subcommand -a export \
    -d 'Export the graph to another format'
complete -c graphify -n __graphify_no_subcommand -a merge-graphs \
    -d 'Merge two or more graph.json files'
complete -c graphify -n __graphify_no_subcommand -a merge-driver \
    -d 'Git merge driver for graph.json (set up by hook install)'
complete -c graphify -n __graphify_no_subcommand -a clone \
    -d 'Clone a GitHub repo and print its path'
complete -c graphify -n __graphify_no_subcommand -a add \
    -d 'Fetch a URL into ./raw and update the graph'
complete -c graphify -n __graphify_no_subcommand -a global \
    -d 'Manage the cross-repo global graph'
complete -c graphify -n __graphify_no_subcommand -a provider \
    -d 'Manage custom LLM providers'
complete -c graphify -n __graphify_no_subcommand -a hook \
    -d 'Install, remove, or check the git hooks'
complete -c graphify -n __graphify_no_subcommand -a benchmark \
    -d 'Measure token reduction vs a naive full-corpus read'
complete -c graphify -n __graphify_no_subcommand -a check-update \
    -d 'Check whether semantic re-extraction is pending'
complete -c graphify -n __graphify_no_subcommand -a install \
    -d 'Copy the skill to a platform config dir'
complete -c graphify -n __graphify_no_subcommand -a uninstall \
    -d 'Remove graphify from every detected platform'

for editor in $gf_editors
    complete -c graphify -n __graphify_no_subcommand -a $editor \
        -d "Install or remove the $editor integration"
end

# --- shared flags ------------------------------------------------------------

complete -c graphify -n '__fish_seen_subcommand_from path explain diagnose query affected god-nodes cluster-only reflect tree' \
    -l graph -r -F -d 'graph.json (default: graphify-out/graph.json)'

complete -c graphify -n '__fish_seen_subcommand_from label cluster-only extract' \
    -l backend -x -a 'azure bedrock claude claude-cli deepseek gemini kimi ollama openai' \
    -d 'LLM backend (default: auto-detect from API keys)'
complete -c graphify -n '__fish_seen_subcommand_from label cluster-only extract' \
    -l model -x -d 'Override the backend default model'
complete -c graphify -n '__fish_seen_subcommand_from label cluster-only extract' \
    -l max-concurrency -x -d 'Parallel LLM calls in flight (default 4)'
complete -c graphify -n '__fish_seen_subcommand_from label cluster-only' \
    -l batch-size -x -d 'Communities per labeling call (default 100)'

complete -c graphify -n '__fish_seen_subcommand_from update extract' \
    -l force -d 'Full re-scan; overwrite even a smaller rebuild'
complete -c graphify -n '__fish_seen_subcommand_from update extract cluster-only' \
    -l no-cluster -d 'Skip clustering, write raw extraction only'

# --- per-command flags -------------------------------------------------------

complete -c graphify -n '__fish_seen_subcommand_from extract' -l mode -x -a deep \
    -d 'Aggressive INFERRED-edge semantic extraction'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l max-workers -x \
    -d 'AST extraction subprocess count (default: cpu_count)'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l token-budget -x \
    -d 'Per-chunk token cap for semantic extraction'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l api-timeout -x \
    -d 'Per-request LLM timeout in seconds (default 600)'
complete -c graphify -n '__fish_seen_subcommand_from extract' -s o -l out -l output -r -F \
    -d 'Output dir; writes <DIR>/graphify-out/'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l postgres -x \
    -d 'Extract schema from a live PostgreSQL database'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l cargo \
    -d 'Extract crate-to-crate deps from Cargo.toml'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l code-only \
    -d 'Index code only; skip doc, paper, and image files'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l no-gitignore \
    -d 'Ignore .gitignore, prioritizing .graphifyignore'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l google-workspace \
    -d 'Export .gdoc/.gsheet/.gslides shortcuts first'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l global \
    -d 'Also merge the result into the global graph'
complete -c graphify -n '__fish_seen_subcommand_from extract' -l as -x \
    -d 'Repo tag for --global (default: directory name)'

complete -c graphify -n '__fish_seen_subcommand_from query' -l dfs \
    -d 'Depth-first instead of breadth-first'
complete -c graphify -n '__fish_seen_subcommand_from query' -l context -x \
    -d 'Explicit edge-context filter (repeatable)'
complete -c graphify -n '__fish_seen_subcommand_from query' -l budget -x \
    -d 'Cap output at N tokens (default 2000)'

complete -c graphify -n '__fish_seen_subcommand_from affected' -l relation -x \
    -d 'Edge relation to traverse in reverse (repeatable)'
complete -c graphify -n '__fish_seen_subcommand_from affected' -l depth -x \
    -d 'Reverse traversal depth (default 2)'

complete -c graphify -n '__fish_seen_subcommand_from god-nodes' -l top -x \
    -d 'How many to show (default 10)'
complete -c graphify -n '__fish_seen_subcommand_from god-nodes diagnose' -l json \
    -d 'Emit machine-readable JSON'

complete -c graphify -n '__fish_seen_subcommand_from label' -l missing-only \
    -d 'Only name missing or placeholder communities'
complete -c graphify -n '__fish_seen_subcommand_from cluster-only' -l no-viz \
    -d 'Skip graph.html generation'
complete -c graphify -n '__fish_seen_subcommand_from cluster-only' -l no-label \
    -d "Keep 'Community N' placeholders"

complete -c graphify -n '__fish_seen_subcommand_from diagnose' -l max-examples -x \
    -d 'Max same-endpoint examples to print (default 5)'
complete -c graphify -n '__fish_seen_subcommand_from diagnose' -l directed \
    -d 'Force a directed post-build simulation'
complete -c graphify -n '__fish_seen_subcommand_from diagnose' -l undirected \
    -d 'Force an undirected post-build simulation'
complete -c graphify -n '__fish_seen_subcommand_from diagnose' -l extract-path -r -F \
    -d 'Extractor source for the suppression scan'

complete -c graphify -n '__fish_seen_subcommand_from save-result' -l question -x \
    -d 'The question asked'
complete -c graphify -n '__fish_seen_subcommand_from save-result' -l answer -x \
    -d 'The answer to save'
complete -c graphify -n '__fish_seen_subcommand_from save-result' -l type -x \
    -a 'query path_query explain' -d 'Query type (default: query)'
complete -c graphify -n '__fish_seen_subcommand_from save-result' -l nodes -x \
    -d 'Node labels cited, copied verbatim from the output'
complete -c graphify -n '__fish_seen_subcommand_from save-result' -l outcome -x \
    -a 'useful dead_end corrected' -d 'Work-memory signal'
complete -c graphify -n '__fish_seen_subcommand_from save-result' -l correction -x \
    -d 'What the right answer was (pairs with --outcome corrected)'
complete -c graphify -n '__fish_seen_subcommand_from save-result reflect' -l memory-dir -r -F \
    -d 'Memory directory (default: graphify-out/memory)'

complete -c graphify -n '__fish_seen_subcommand_from reflect' -l out -r -F \
    -d 'Output path (default: graphify-out/reflections/LESSONS.md)'
complete -c graphify -n '__fish_seen_subcommand_from reflect' -l analysis -r -F \
    -d '.graphify_analysis.json (auto-detected next to --graph)'
complete -c graphify -n '__fish_seen_subcommand_from reflect' -l labels -r -F \
    -d '.graphify_labels.json (auto-detected next to --graph)'
complete -c graphify -n '__fish_seen_subcommand_from reflect' -l half-life-days -x \
    -d 'Signal weight halves every N days (default 30)'
complete -c graphify -n '__fish_seen_subcommand_from reflect' -l min-corroboration -x \
    -d 'Distinct useful results to prefer a node (default 2)'

complete -c graphify -n '__fish_seen_subcommand_from tree' -l output -r -F \
    -d 'Output path (default: graphify-out/GRAPH_TREE.html)'
complete -c graphify -n '__fish_seen_subcommand_from tree' -l root -r -F \
    -d 'Filesystem root for the hierarchy'
complete -c graphify -n '__fish_seen_subcommand_from tree' -l max-children -x \
    -d 'Cap children per node (default 200)'
complete -c graphify -n '__fish_seen_subcommand_from tree' -l top-k-edges -x \
    -d 'Per-symbol outbound edges in the inspector (default 12)'
complete -c graphify -n '__fish_seen_subcommand_from tree' -l label -x \
    -d 'Project label in the header'

complete -c graphify -n '__fish_seen_subcommand_from add' -l author -x -d 'Tag the author'
complete -c graphify -n '__fish_seen_subcommand_from add' -l contributor -x \
    -d 'Tag who added it to the corpus'
complete -c graphify -n '__fish_seen_subcommand_from add clone' -l dir -l out -r -F \
    -d 'Target directory'
complete -c graphify -n '__fish_seen_subcommand_from clone' -l branch -x \
    -d 'Checkout a specific branch (default: repo default)'
complete -c graphify -n '__fish_seen_subcommand_from merge-graphs' -l out -r -F \
    -d 'Output path (default: graphify-out/merged-graph.json)'

complete -c graphify -n '__fish_seen_subcommand_from install' -l platform -x -a "$gf_platforms" \
    -d 'Platform config dir to copy the skill into'
complete -c graphify -n '__fish_seen_subcommand_from uninstall' -l purge \
    -d 'Also delete the graphify-out/ directory'

# --- subcommand words --------------------------------------------------------

complete -c graphify -n '__graphify_bare_command export' \
    -a 'callflow-html html obsidian wiki svg graphml neo4j falkordb' -d 'Export format'

complete -c graphify -n '__graphify_bare_command global' \
    -a 'add remove list path' -d 'Global-graph action'

complete -c graphify -n '__graphify_bare_command provider' \
    -a 'list show add remove' -d 'Provider action'

complete -c graphify -n '__graphify_bare_command hook' \
    -a 'install uninstall status' -d 'Git-hook action'

for editor in $gf_editors
    complete -c graphify -n "__graphify_bare_command $editor" \
        -a 'install uninstall' -d "$editor integration"
end
