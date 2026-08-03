# Fish completions for the `claude` CLI (Claude Code).
# Generated against claude 2.1.220.

complete -c claude -f

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Command path of the current commandline, starting at the first recognised
# subcommand so that values of global options (`--model opus mcp list`) do not
# shift the path. Aliases are normalised to their canonical name.
function __claude_path
    set -l tokens (commandline -opc)
    set -e tokens[1]
    set -l roots agents auth auto-mode doctor gateway install mcp plugin plugins project setup-token ultrareview update upgrade
    set -l path
    for t in $tokens
        if test (count $path) -eq 0
            contains -- $t $roots; or continue
        end
        string match -q -- '-*' $t; and continue
        switch $t
            case plugins
                set t plugin
            case upgrade
                set t update
            case new
                set t init
            case i
                set t install
            case rm
                set t remove
            case autoremove
                set t prune
        end
        set -a path $t
    end
    for p in $path
        echo $p
    end
    return 0
end

# True while no subcommand has been typed yet.
function __claude_root
    set -l path (__claude_path)
    test (count $path) -eq 0
end

# True when the command path starts with the given words.
function __claude_cmd
    set -l path (__claude_path)
    test (count $path) -ge (count $argv); or return 1
    for i in (seq (count $argv))
        test "$path[$i]" = "$argv[$i]"; or return 1
    end
    return 0
end

# True when the command path is exactly the given words — used to offer the
# next level of subcommands and nothing deeper.
function __claude_at
    set -l path (__claude_path)
    test (count $path) -eq (count $argv); or return 1
    __claude_cmd $argv
end

function __claude_sessions
    set -l proj (pwd | string replace -ra '[^a-zA-Z0-9]' -)
    set -l dir "$HOME/.claude/projects/$proj"
    test -d "$dir"; or return 0
    set -l files $dir/*.jsonl
    test (count $files) -gt 0; or return 0
    for f in $files
        jq -rs '
              (map(select(.type=="custom-title")) | last | .customTitle) as $custom
              | (map(select(.type=="ai-title")) | last | .aiTitle) as $ai
              | (map(select(.type=="last-prompt")) | last | .lastPrompt) as $prompt
              | (map(.sessionId) | map(select(. != null)) | last) as $sid
              | select($sid != null)
              | (if ($custom // "") != "" then $custom
                 elif ($ai // "") != "" then $ai
                 else $sid end) as $name
              | "\($name | gsub("[ \t\n\r]+"; " "))\t\((($prompt // "") | gsub("[ \t\n\r]+"; " "))[0:60])"
          ' "$f" 2>/dev/null
    end
    return 0
end

function __claude_agents
    for dir in ./.claude/agents "$HOME/.claude/agents"
        test -d $dir; or continue
        for f in $dir/*.md
            test -f "$f"; or continue
            basename "$f" .md
        end
    end
    return 0
end

set -l __claude_models fable opus sonnet haiku claude-fable-5 claude-opus-5 claude-sonnet-5 claude-haiku-4-5
set -l __claude_tools default Bash Edit Write Read Glob Grep Agent WebFetch WebSearch NotebookEdit TodoWrite Skill
set -l __claude_scopes local user project

# ---------------------------------------------------------------------------
# Top-level options
# ---------------------------------------------------------------------------

complete -c claude -n __claude_root -l add-dir -r -a '(__fish_complete_directories)' -d 'Additional directories to allow tool access to'
complete -c claude -n __claude_root -l agent -x -a '(__claude_agents)' -d 'Agent for the current session'
complete -c claude -n __claude_root -l agents -x -d 'JSON object defining custom agents'
complete -c claude -n __claude_root -l allow-dangerously-skip-permissions -d 'Make bypass-permissions available without enabling it by default'
complete -c claude -n __claude_root -l allowedTools -l allowed-tools -x -a "$__claude_tools" -d 'Tool names to allow (comma or space separated)'
complete -c claude -n __claude_root -l append-system-prompt -x -d 'Append a system prompt to the default system prompt'
complete -c claude -n __claude_root -l ax-screen-reader -d 'Render screen-reader friendly output'
complete -c claude -n __claude_root -l bg -l background -d 'Start the session as a background agent and return immediately'
complete -c claude -n __claude_root -l bare -d 'Minimal mode: skip hooks, LSP, plugins, auto-memory, CLAUDE.md discovery'
complete -c claude -n __claude_root -l betas -x -d 'Beta headers to include in API requests (API key users only)'
complete -c claude -n __claude_root -l brief -d 'Enable SendUserMessage tool for agent-to-user communication'
complete -c claude -n __claude_root -l chrome -d 'Enable Claude in Chrome integration'
complete -c claude -n __claude_root -s c -l continue -d 'Continue the most recent conversation in the current directory'
complete -c claude -n __claude_root -l dangerously-skip-permissions -d 'Bypass all permission checks'
complete -c claude -n __claude_root -s d -l debug -d 'Enable debug mode with optional category filtering'
complete -c claude -n __claude_root -l debug-file -rF -d 'Write debug logs to a specific file path'
complete -c claude -n __claude_root -l disable-slash-commands -d 'Disable all skills'
complete -c claude -n __claude_root -l disallowedTools -l disallowed-tools -x -a "$__claude_tools" -d 'Tool names to deny (comma or space separated)'
complete -c claude -n __claude_root -l effort -x -a 'low medium high xhigh max' -d 'Effort level for the current session'
complete -c claude -n __claude_root -l exclude-dynamic-system-prompt-sections -d 'Move per-machine sections into the first user message'
complete -c claude -n __claude_root -l fallback-model -x -a "$__claude_models" -d 'Fallback model(s) when the default is overloaded (--print only)'
complete -c claude -n __claude_root -l file -r -d 'File resources to download at startup (file_id:relative_path)'
complete -c claude -n __claude_root -l fork-session -d 'When resuming, create a new session ID instead of reusing the original'
complete -c claude -n __claude_root -l forward-subagent-text -d 'Forward subagent text and thinking blocks as messages'
complete -c claude -n __claude_root -l from-pr -d 'Resume a session linked to a PR by number/URL, or open the picker'
complete -c claude -n __claude_root -s h -l help -d 'Display help for command'
complete -c claude -n __claude_root -l ide -d 'Connect to IDE on startup if exactly one valid IDE is available'
complete -c claude -n __claude_root -l include-hook-events -d 'Include all hook lifecycle events in the output stream'
complete -c claude -n __claude_root -l include-partial-messages -d 'Include partial message chunks as they arrive'
complete -c claude -n __claude_root -l input-format -x -a 'text stream-json' -d 'Input format (--print only)'
complete -c claude -n __claude_root -l json-schema -x -d 'JSON Schema for structured output validation'
complete -c claude -n __claude_root -l max-budget-usd -x -d 'Maximum dollar amount to spend on API calls (--print only)'
complete -c claude -n __claude_root -l mcp-config -rF -d 'Load MCP servers from JSON files or strings'
complete -c claude -n __claude_root -l model -x -a "$__claude_models" -d 'Model for the current session'
complete -c claude -n __claude_root -s n -l name -x -d 'Display name for this session'
complete -c claude -n __claude_root -l no-chrome -d 'Disable Claude in Chrome integration'
complete -c claude -n __claude_root -l no-session-persistence -d 'Do not save the session to disk (--print only)'
complete -c claude -n __claude_root -l output-format -x -a 'text json stream-json' -d 'Output format (--print only)'
complete -c claude -n __claude_root -l permission-mode -x -a 'acceptEdits auto bypassPermissions manual dontAsk plan' -d 'Permission mode for the session'
complete -c claude -n __claude_root -l plugin-dir -rF -d 'Load a plugin from a directory or .zip for this session only'
complete -c claude -n __claude_root -l plugin-url -x -d 'Fetch a plugin .zip from a URL for this session only'
complete -c claude -n __claude_root -s p -l print -d 'Print response and exit (useful for pipes)'
complete -c claude -n __claude_root -l prompt-suggestions -d 'Enable prompt suggestions'
complete -c claude -n __claude_root -l remote-control -d 'Start an interactive session with Remote Control enabled'
complete -c claude -n __claude_root -l remote-control-session-name-prefix -x -d 'Prefix for auto-generated Remote Control session names'
complete -c claude -n __claude_root -l replay-user-messages -d 'Re-emit user messages from stdin back on stdout'
complete -c claude -n __claude_root -s r -l resume -rfa '(__claude_sessions)' -d 'Resume a conversation by session ID, or open the picker'
complete -c claude -n __claude_root -l safe-mode -d 'Start with all customizations disabled (troubleshooting)'
complete -c claude -n __claude_root -l session-id -x -d 'Use a specific session ID (must be a valid UUID)'
complete -c claude -n __claude_root -l setting-sources -x -a 'user project local' -d 'Comma-separated list of setting sources to load'
complete -c claude -n __claude_root -l settings -rF -d 'Path to a settings JSON file or a JSON string'
complete -c claude -n __claude_root -l strict-mcp-config -d 'Only use MCP servers from --mcp-config'
complete -c claude -n __claude_root -l system-prompt -x -d 'System prompt to use for the session'
complete -c claude -n __claude_root -l tmux -d 'Create a tmux session for the worktree (requires --worktree)'
complete -c claude -n __claude_root -l tools -x -a "$__claude_tools" -d 'Available tools from the built-in set'
complete -c claude -n __claude_root -l verbose -d 'Override verbose mode setting from config'
complete -c claude -n __claude_root -s v -l version -d 'Output the version number'
complete -c claude -n __claude_root -s w -l worktree -d 'Create a new git worktree for this session'

# ---------------------------------------------------------------------------
# Top-level subcommands
# ---------------------------------------------------------------------------

complete -c claude -n __claude_root -a agents -d 'Manage background agents'
complete -c claude -n __claude_root -a auth -d 'Manage authentication'
complete -c claude -n __claude_root -a auto-mode -d 'Inspect or reset auto mode classifier configuration'
complete -c claude -n __claude_root -a doctor -d 'Check the health of your Claude Code installation'
complete -c claude -n __claude_root -a gateway -d 'Run the enterprise auth/telemetry gateway'
complete -c claude -n __claude_root -a install -d 'Install Claude Code native build'
complete -c claude -n __claude_root -a mcp -d 'Configure and manage MCP servers'
complete -c claude -n __claude_root -a plugin -d 'Manage Claude Code plugins'
complete -c claude -n __claude_root -a project -d 'Manage Claude Code project state'
complete -c claude -n __claude_root -a setup-token -d 'Set up a long-lived authentication token'
complete -c claude -n __claude_root -a ultrareview -d 'Run a cloud-hosted multi-agent code review and print findings'
complete -c claude -n __claude_root -a update -d 'Check for updates and install if available'

# ---------------------------------------------------------------------------
# claude agents
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_cmd agents' -l add-dir -r -a '(__fish_complete_directories)' -d 'Extra directory allowed in dispatched sessions (repeatable)'
complete -c claude -n '__claude_cmd agents' -l agent -x -a '(__claude_agents)' -d 'Default agent for dispatched sessions'
complete -c claude -n '__claude_cmd agents' -l all -d 'With --json: also include completed background sessions'
complete -c claude -n '__claude_cmd agents' -l allow-dangerously-skip-permissions -d 'Make bypass-permissions available to dispatched sessions'
complete -c claude -n '__claude_cmd agents' -l cwd -r -a '(__fish_complete_directories)' -d 'Show only background sessions started under this path'
complete -c claude -n '__claude_cmd agents' -l dangerously-skip-permissions -d 'Alias for --permission-mode bypassPermissions'
complete -c claude -n '__claude_cmd agents' -l effort -x -a 'low medium high xhigh max' -d 'Default effort level for dispatched sessions'
complete -c claude -n '__claude_cmd agents' -s h -l help -d 'Display help for command'
complete -c claude -n '__claude_cmd agents' -l json -d 'Print active sessions as a JSON array and exit'
complete -c claude -n '__claude_cmd agents' -l mcp-config -rF -d 'MCP server configuration for dispatched sessions (repeatable)'
complete -c claude -n '__claude_cmd agents' -l model -x -a "$__claude_models" -d 'Default model for dispatched sessions'
complete -c claude -n '__claude_cmd agents' -l permission-mode -x -a 'acceptEdits auto bypassPermissions manual dontAsk plan' -d 'Default permission mode for dispatched sessions'
complete -c claude -n '__claude_cmd agents' -l plugin-dir -rF -d 'Load plugins from a directory for the agent view (repeatable)'
complete -c claude -n '__claude_cmd agents' -l setting-sources -x -a 'user project local' -d 'Comma-separated list of setting sources to load'
complete -c claude -n '__claude_cmd agents' -l settings -rF -d 'Settings file or JSON string for the agent view'
complete -c claude -n '__claude_cmd agents' -l strict-mcp-config -d 'Only use MCP servers from --mcp-config in dispatched sessions'

# ---------------------------------------------------------------------------
# claude auth
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_at auth' -a login -d 'Sign in to your Anthropic account'
complete -c claude -n '__claude_at auth' -a logout -d 'Log out from your Anthropic account'
complete -c claude -n '__claude_at auth' -a status -d 'Show authentication status'
complete -c claude -n '__claude_at auth' -a help -d 'Display help for a subcommand'
complete -c claude -n '__claude_cmd auth' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd auth login' -l claudeai -d 'Use Claude subscription (default)'
complete -c claude -n '__claude_cmd auth login' -l console -d 'Use Anthropic Console (API usage billing)'
complete -c claude -n '__claude_cmd auth login' -l email -x -d 'Pre-populate email address on the login page'
complete -c claude -n '__claude_cmd auth login' -l sso -d 'Force SSO login flow'

complete -c claude -n '__claude_cmd auth status' -l json -d 'Output as JSON (default)'
complete -c claude -n '__claude_cmd auth status' -l text -d 'Output as human-readable text'

# ---------------------------------------------------------------------------
# claude auto-mode
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_at auto-mode' -a config -d 'Print the effective auto mode config as JSON'
complete -c claude -n '__claude_at auto-mode' -a critique -d 'Get AI feedback on your custom auto mode rules'
complete -c claude -n '__claude_at auto-mode' -a defaults -d 'Print the default auto mode rules as JSON'
complete -c claude -n '__claude_at auto-mode' -a reset -d 'Reset auto mode configuration to the shipped defaults'
complete -c claude -n '__claude_at auto-mode' -a help -d 'Display help for a subcommand'
complete -c claude -n '__claude_cmd auto-mode' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd auto-mode critique' -l model -x -a "$__claude_models" -d 'Override which model is used'
complete -c claude -n '__claude_cmd auto-mode defaults' -l label -x -d 'Show only rules whose label starts with this prefix'
complete -c claude -n '__claude_cmd auto-mode reset' -s y -l yes -d 'Skip the confirmation prompt'

# ---------------------------------------------------------------------------
# claude doctor / gateway / install / setup-token / ultrareview / update
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_cmd doctor' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd gateway' -l config -rF -d 'Path to gateway YAML config'
complete -c claude -n '__claude_cmd gateway' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_at install' -a 'stable latest' -d 'Version to install'
complete -c claude -n '__claude_cmd install' -l force -d 'Force installation even if already installed'
complete -c claude -n '__claude_cmd install' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd setup-token' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd ultrareview' -s h -l help -d 'Display help for command'
complete -c claude -n '__claude_cmd ultrareview' -l json -d 'Print the raw bugs.json payload instead of formatted findings'
complete -c claude -n '__claude_cmd ultrareview' -l timeout -x -d 'Maximum minutes to wait for the review to finish (default 30)'

complete -c claude -n '__claude_cmd update' -s h -l help -d 'Display help for command'

# ---------------------------------------------------------------------------
# claude mcp
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_at mcp' -a add -d 'Add an MCP server to Claude Code'
complete -c claude -n '__claude_at mcp' -a add-from-claude-desktop -d 'Import MCP servers from Claude Desktop (Mac and WSL only)'
complete -c claude -n '__claude_at mcp' -a add-json -d 'Add an MCP server with a JSON string'
complete -c claude -n '__claude_at mcp' -a get -d 'Get details about an MCP server'
complete -c claude -n '__claude_at mcp' -a list -d 'List configured MCP servers'
complete -c claude -n '__claude_at mcp' -a login -d 'Authenticate with an MCP server'
complete -c claude -n '__claude_at mcp' -a logout -d 'Clear stored OAuth credentials for an MCP server'
complete -c claude -n '__claude_at mcp' -a remove -d 'Remove an MCP server'
complete -c claude -n '__claude_at mcp' -a reset-project-choices -d 'Reset approved and rejected project-scoped servers'
complete -c claude -n '__claude_at mcp' -a serve -d 'Start the Claude Code MCP server'
complete -c claude -n '__claude_at mcp' -a help -d 'Display help for a subcommand'
complete -c claude -n '__claude_cmd mcp' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd mcp add' -l callback-port -x -d 'Fixed port for the OAuth callback'
complete -c claude -n '__claude_cmd mcp add' -l client-id -x -d 'OAuth client ID for HTTP/SSE servers'
complete -c claude -n '__claude_cmd mcp add' -l client-secret -d 'Prompt for the OAuth client secret'
complete -c claude -n '__claude_cmd mcp add' -s e -l env -x -d 'Set environment variables (KEY=value)'
complete -c claude -n '__claude_cmd mcp add' -s H -l header -x -d 'Set headers (Name: value)'
complete -c claude -n '__claude_cmd mcp add' -s s -l scope -x -a "$__claude_scopes" -d 'Configuration scope (default local)'
complete -c claude -n '__claude_cmd mcp add' -s t -l transport -x -a 'stdio sse http' -d 'Transport type (default stdio)'

complete -c claude -n '__claude_cmd mcp add-from-claude-desktop' -s s -l scope -x -a "$__claude_scopes" -d 'Configuration scope (default local)'

complete -c claude -n '__claude_cmd mcp add-json' -l client-secret -d 'Prompt for the OAuth client secret'
complete -c claude -n '__claude_cmd mcp add-json' -s s -l scope -x -a "$__claude_scopes" -d 'Configuration scope (default local)'

complete -c claude -n '__claude_cmd mcp login' -l no-browser -d 'Print the authorization URL instead of opening a browser'

complete -c claude -n '__claude_cmd mcp remove' -s s -l scope -x -a "$__claude_scopes" -d 'Configuration scope to remove from'

complete -c claude -n '__claude_cmd mcp serve' -s d -l debug -d 'Enable debug mode'
complete -c claude -n '__claude_cmd mcp serve' -l verbose -d 'Override verbose mode setting from config'

# ---------------------------------------------------------------------------
# claude plugin
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_at plugin' -a details -d 'Show a plugin component inventory and projected token cost'
complete -c claude -n '__claude_at plugin' -a disable -d 'Disable an enabled plugin'
complete -c claude -n '__claude_at plugin' -a enable -d 'Enable a disabled plugin'
complete -c claude -n '__claude_at plugin' -a eval -d 'Run eval cases against a plugin and report scored results'
complete -c claude -n '__claude_at plugin' -a init -d 'Scaffold a new plugin under ~/.claude/skills/'
complete -c claude -n '__claude_at plugin' -a install -d 'Install a plugin from available marketplaces'
complete -c claude -n '__claude_at plugin' -a list -d 'List installed plugins'
complete -c claude -n '__claude_at plugin' -a marketplace -d 'Manage Claude Code marketplaces'
complete -c claude -n '__claude_at plugin' -a prune -d 'Remove auto-installed dependencies that are no longer needed'
complete -c claude -n '__claude_at plugin' -a tag -d 'Create a name--vversion git tag for a plugin release'
complete -c claude -n '__claude_at plugin' -a uninstall -d 'Uninstall an installed plugin'
complete -c claude -n '__claude_at plugin' -a update -d 'Update a plugin to the latest version'
complete -c claude -n '__claude_at plugin' -a validate -d 'Validate a plugin or marketplace manifest'
complete -c claude -n '__claude_at plugin' -a help -d 'Display help for a subcommand'
complete -c claude -n '__claude_cmd plugin' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd plugin disable' -s a -l all -d 'Disable all enabled plugins'
complete -c claude -n '__claude_cmd plugin disable' -s s -l scope -x -a "$__claude_scopes" -d 'Installation scope (default auto-detect)'
complete -c claude -n '__claude_cmd plugin enable' -s s -l scope -x -a "$__claude_scopes" -d 'Installation scope (default auto-detect)'

complete -c claude -n '__claude_at plugin eval' -a init -d 'Author an eval suite under evals/ via an interview'
complete -c claude -n '__claude_cmd plugin eval init' -l bare -d 'Write a blank template instead of running the interview'

set -l __claude_eval '__claude_cmd plugin eval; and not __claude_cmd plugin eval init'
complete -c claude -n $__claude_eval -l ablation -x -a 'none with-without' -d 'Run a no-plugin baseline arm and report the score delta'
complete -c claude -n $__claude_eval -l allow-tools -x -a "$__claude_tools" -d 'Operator grant for gated tools'
complete -c claude -n $__claude_eval -l case -x -d 'Filter cases by name glob'
complete -c claude -n $__claude_eval -l json -rF -d 'Print the full run result as JSON, or write it to a .json file'
complete -c claude -n $__claude_eval -l judge-model -x -a "$__claude_models" -d 'Override the LLM-grader model (default haiku)'
complete -c claude -n $__claude_eval -l keep-temp -d 'Preserve scaffold dirs for debugging'
complete -c claude -n $__claude_eval -l max-cost-usd -x -d 'Hard cost ceiling; abort and report partial results if hit'
complete -c claude -n $__claude_eval -l model -x -a "$__claude_models" -d 'Override model for all cases'
complete -c claude -n $__claude_eval -l no-scaffold -d 'Explicitly skip scaffold_script'
complete -c claude -n $__claude_eval -l output-dir -r -a '(__fish_complete_directories)' -d 'Directory for aggregate-result.json'
complete -c claude -n $__claude_eval -l publish-report -d 'Publish the HTML report privately to claude.ai and print its link'
complete -c claude -n $__claude_eval -l report -rF -d 'Write a self-contained HTML report to this path'
complete -c claude -n $__claude_eval -l runs -x -d 'Override per-case runs (default case.runs or 3)'
complete -c claude -n $__claude_eval -l scaffold -d 'Run each case scaffold_script (runs author-supplied bash as you)'
complete -c claude -n $__claude_eval -l tag -x -d 'Filter cases by tag (repeatable)'
complete -c claude -n $__claude_eval -l threshold -x -d 'Exit 1 if any case score is below this threshold (default 1.0)'
complete -c claude -n $__claude_eval -l verbose -d 'Stream the trace as it runs'

complete -c claude -n '__claude_cmd plugin init' -l author -x -d 'Author name (default git config user.name)'
complete -c claude -n '__claude_cmd plugin init' -l author-email -x -d 'Author email (default git config user.email)'
complete -c claude -n '__claude_cmd plugin init' -l description -x -d 'Manifest description'
complete -c claude -n '__claude_cmd plugin init' -s f -l force -d 'Overwrite an existing .claude-plugin/ at the target'
complete -c claude -n '__claude_cmd plugin init' -l with -x -a 'skills agents hooks mcp lsp output-style channel' -d 'Also scaffold these components'

complete -c claude -n '__claude_cmd plugin install' -l config -x -d 'Set a userConfig option declared in the manifest (key=value)'
complete -c claude -n '__claude_cmd plugin install' -s s -l scope -x -a 'user project local' -d 'Installation scope (default user)'

complete -c claude -n '__claude_cmd plugin list' -l available -d 'Include available plugins from marketplaces (requires --json)'
complete -c claude -n '__claude_cmd plugin list' -l json -d 'Output as JSON'

complete -c claude -n '__claude_cmd plugin prune' -l dry-run -d 'List what would be removed without removing'
complete -c claude -n '__claude_cmd plugin prune' -s s -l scope -x -a 'user project local' -d 'Prune at scope (default user)'
complete -c claude -n '__claude_cmd plugin prune' -s y -l yes -d 'Skip the confirmation prompt'

complete -c claude -n '__claude_cmd plugin tag' -l dry-run -d 'Print what would be tagged without creating it'
complete -c claude -n '__claude_cmd plugin tag' -s f -l force -d 'Skip the dirty-tree and tag-already-exists checks'
complete -c claude -n '__claude_cmd plugin tag' -s m -l message -x -d 'Tag annotation message (use %s for the version)'
complete -c claude -n '__claude_cmd plugin tag' -l push -d 'Push the tag to --remote after creating it'
complete -c claude -n '__claude_cmd plugin tag' -l remote -x -d 'Remote to push to with --push (default origin)'

complete -c claude -n '__claude_cmd plugin uninstall' -l keep-data -d 'Preserve the plugin persistent data directory'
complete -c claude -n '__claude_cmd plugin uninstall' -l prune -d 'Also remove auto-installed dependencies no longer needed'
complete -c claude -n '__claude_cmd plugin uninstall' -s s -l scope -x -a 'user project local' -d 'Uninstall from scope (default user)'
complete -c claude -n '__claude_cmd plugin uninstall' -s y -l yes -d 'Skip the --prune confirmation prompt'

complete -c claude -n '__claude_cmd plugin update' -s s -l scope -x -a 'user project local managed' -d 'Installation scope (default user)'

complete -c claude -n '__claude_cmd plugin validate' -l strict -d 'Treat warnings as errors (exit 1)'
complete -c claude -n '__claude_cmd plugin validate' -rF -d 'Plugin or marketplace manifest path'

complete -c claude -n '__claude_at plugin marketplace' -a add -d 'Add a marketplace from a URL, path, or GitHub repo'
complete -c claude -n '__claude_at plugin marketplace' -a list -d 'List all configured marketplaces'
complete -c claude -n '__claude_at plugin marketplace' -a remove -d 'Remove a configured marketplace'
complete -c claude -n '__claude_at plugin marketplace' -a update -d 'Update marketplace(s) from their source'
complete -c claude -n '__claude_at plugin marketplace' -a help -d 'Display help for a subcommand'

complete -c claude -n '__claude_cmd plugin marketplace add' -l scope -x -a 'user project local' -d 'Where to declare the marketplace (default user)'
complete -c claude -n '__claude_cmd plugin marketplace add' -l sparse -x -d 'Limit checkout to specific directories via git sparse-checkout'
complete -c claude -n '__claude_cmd plugin marketplace list' -l json -d 'Output as JSON'
complete -c claude -n '__claude_cmd plugin marketplace remove' -l scope -x -a 'user project local' -d 'Settings scope to remove the declaration from'

# ---------------------------------------------------------------------------
# claude project
# ---------------------------------------------------------------------------

complete -c claude -n '__claude_at project' -a purge -d 'Delete all Claude Code state for a project'
complete -c claude -n '__claude_at project' -a help -d 'Display help for a subcommand'
complete -c claude -n '__claude_cmd project' -s h -l help -d 'Display help for command'

complete -c claude -n '__claude_cmd project purge' -l all -d 'Purge state for every project'
complete -c claude -n '__claude_cmd project purge' -l dry-run -d 'List what would be deleted without deleting anything'
complete -c claude -n '__claude_cmd project purge' -s i -l interactive -d 'Prompt for each item before deleting'
complete -c claude -n '__claude_cmd project purge' -s y -l yes -d 'Skip confirmation prompt'
complete -c claude -n '__claude_cmd project purge' -r -a '(__fish_complete_directories)' -d 'Project path'
