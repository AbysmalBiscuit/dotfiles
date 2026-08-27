# Completions for `claude`, which carapace has no spec for. One command per
# file under lib/completions/; config.nu sources the directory.
#
# Ported from ~/.config/fish/completions/claude.fish. An `extern` here does
# three jobs a carapace bridge cannot: it names the flags in the completion
# menu with their descriptions, it drives subcommand completion, and it is what
# an alias inherits. That last one is why config.nu sources this before
# lib/aliases.nu instead of dropping it in the autoload directory: an alias
# binds to whatever declaration exists when the alias is parsed, and autoload
# runs after config.nu.
#
# Externs stay permissive. An undeclared flag or an extra positional is passed
# through untouched, so a signature that lags behind the CLI costs completions,
# not a broken command. The one way to break a real invocation is to give a
# flag a value type when the flag's value is optional: `--resume(-r): string`
# turns a bare `claude -r` into a parse error. Those flags are declared as
# switches, and their values are completed from the positional instead.

# ---------------------------------------------------------------------------
# claude
# ---------------------------------------------------------------------------

# The command line as words, with a leading alias resolved. A completer is
# handed the raw buffer, so `cr ` arrives as "cr " rather than "claude -r ".
def "nu-complete claude words" [context: string] {
    let words = ($context | str trim --left | split row --regex '\s+')
    let head = ($words | get --optional 0 | default "")
    let expansion = (scope aliases | where name == $head | get --optional 0.expansion)
    if ($expansion | is-not-empty) {
        ($expansion | split row --regex '\s+') ++ ($words | skip 1)
    } else {
        $words
    }
}

# Resumable sessions for the current directory, newest first. The transcript
# file name is the session id `--resume` wants; the titles only ever reach the
# description column. rg first because a transcript runs to megabytes and only
# a handful of its lines carry a title.
def "nu-complete claude sessions" [] {
    let dir = ($nu.home-dir | path join ".claude" "projects" ($env.PWD | str replace --all --regex '[^a-zA-Z0-9]' "-"))
    if not ($dir | path exists) { return [] }

    ls --full-paths $"($dir)/*.jsonl"
    | sort-by modified --reverse
    | each {|f|
        let meta = (
            do --ignore-errors { ^rg -N '"type":"(ai-title|custom-title|last-prompt)"' $f.name }
            | default ""
            | lines
            | each { try { $in | from json } catch { null } }
            | compact
        )
        let custom = ($meta | where type == "custom-title" | get --optional customTitle | compact | reverse | get --optional 0 | default "")
        let ai = ($meta | where type == "ai-title" | get --optional aiTitle | compact | reverse | get --optional 0 | default "")
        let title = (if $custom != "" { $custom } else { $ai })
        let prompt = (
            $meta | where type == "last-prompt" | get --optional lastPrompt | compact | reverse | get --optional 0 | default ""
            | str replace --all --regex '\s+' " " | str substring 0..60
        )
        {
            value: ($f.name | path basename | str replace ".jsonl" "")
            description: ([$title $prompt] | where {|s| $s != "" } | str join "  ")
        }
    }
}

# Agent names, project before user, the order claude itself resolves them in.
def "nu-complete claude agents" [] {
    [".claude/agents" ($nu.home-dir | path join ".claude" "agents")]
    | where {|d| $d | path exists }
    | each {|d| ls --full-paths $"($d)/*.md" | get name | path basename | str replace ".md" "" }
    | flatten
    | uniq
}

def "nu-complete claude models" [] {
    ["fable" "opus" "sonnet" "haiku" "claude-fable-5" "claude-opus-5" "claude-sonnet-5" "claude-haiku-4-5"]
}

def "nu-complete claude tools" [] {
    ["default" "Bash" "Edit" "Write" "Read" "Glob" "Grep" "Agent" "WebFetch" "WebSearch" "NotebookEdit" "TodoWrite" "Skill"]
}

def "nu-complete claude scopes" [] { ["local" "user" "project"] }
def "nu-complete claude install-scopes" [] { ["user" "project" "local"] }
def "nu-complete claude update-scopes" [] { ["user" "project" "local" "managed"] }
def "nu-complete claude effort" [] { ["low" "medium" "high" "xhigh" "max"] }
def "nu-complete claude permission-modes" [] { ["acceptEdits" "auto" "bypassPermissions" "manual" "dontAsk" "plan"] }

# `--resume` and `--print` both take an optional value, so they are declared as
# switches and their argument lands on this positional instead. Returning an
# empty list rather than null keeps file completion off, matching fish's
# `complete -c claude -f`; subcommand completion is unaffected either way.
def "nu-complete claude prompt" [context: string] {
    let words = (nu-complete claude words $context)
    let prev = ($words | drop 1 | last | default "")
    if $prev in ["-r" "--resume"] {
        {
            options: { sort: false, match_description: true }
            completions: (nu-complete claude sessions)
        }
    } else {
        []
    }
}

# Claude Code
export extern claude [
    --add-dir: directory                                    # Additional directories to allow tool access to
    --agent: string@"nu-complete claude agents"             # Agent for the current session
    --agents: string                                        # JSON object defining custom agents
    --allow-dangerously-skip-permissions                    # Make bypass-permissions available without enabling it by default
    --allowed-tools: string@"nu-complete claude tools"      # Tool names to allow (comma or space separated)
    --append-system-prompt: string                          # Append a system prompt to the default system prompt
    --ax-screen-reader                                      # Render screen-reader friendly output
    --background                                            # Start the session as a background agent and return immediately
    --bare                                                  # Minimal mode: skip hooks, LSP, plugins, auto-memory, CLAUDE.md discovery
    --betas: string                                         # Beta headers to include in API requests (API key users only)
    --brief                                                 # Enable SendUserMessage tool for agent-to-user communication
    --chrome                                                # Enable Claude in Chrome integration
    --continue(-c)                                          # Continue the most recent conversation in the current directory
    --dangerously-skip-permissions                          # Bypass all permission checks
    --debug(-d)                                             # Enable debug mode with optional category filtering
    --debug-file: path                                      # Write debug logs to a specific file path
    --disable-slash-commands                                # Disable all skills
    --disallowed-tools: string@"nu-complete claude tools"   # Tool names to deny (comma or space separated)
    --effort: string@"nu-complete claude effort"            # Effort level for the current session
    --exclude-dynamic-system-prompt-sections                # Move per-machine sections into the first user message
    --fallback-model: string@"nu-complete claude models"    # Fallback model(s) when the default is overloaded (--print only)
    --file: string                                          # File resources to download at startup (file_id:relative_path)
    --fork-session                                          # When resuming, create a new session ID instead of reusing the original
    --forward-subagent-text                                 # Forward subagent text and thinking blocks as messages
    --from-pr                                               # Resume a session linked to a PR by number/URL, or open the picker
    --help(-h)                                              # Display help for command
    --ide                                                   # Connect to IDE on startup if exactly one valid IDE is available
    --include-hook-events                                   # Include all hook lifecycle events in the output stream
    --include-partial-messages                              # Include partial message chunks as they arrive
    --input-format: string@"nu-complete claude input-format"    # Input format (--print only)
    --json-schema: string                                   # JSON Schema for structured output validation
    --max-budget-usd: string                                # Maximum dollar amount to spend on API calls (--print only)
    --mcp-config: path                                      # Load MCP servers from JSON files or strings
    --model: string@"nu-complete claude models"             # Model for the current session
    --name(-n): string                                      # Display name for this session
    --no-chrome                                             # Disable Claude in Chrome integration
    --no-session-persistence                                # Do not save the session to disk (--print only)
    --output-format: string@"nu-complete claude output-format"  # Output format (--print only)
    --permission-mode: string@"nu-complete claude permission-modes" # Permission mode for the session
    --plugin-dir: directory                                 # Load a plugin from a directory or .zip for this session only
    --plugin-url: string                                    # Fetch a plugin .zip from a URL for this session only
    --print(-p)                                             # Print response and exit (useful for pipes)
    --prompt-suggestions                                    # Enable prompt suggestions
    --remote-control                                        # Start an interactive session with Remote Control enabled
    --remote-control-session-name-prefix: string            # Prefix for auto-generated Remote Control session names
    --replay-user-messages                                  # Re-emit user messages from stdin back on stdout
    --resume(-r)                                            # Resume a conversation by session ID, or open the picker
    --safe-mode                                             # Start with all customizations disabled (troubleshooting)
    --session-id: string                                    # Use a specific session ID (must be a valid UUID)
    --setting-sources: string@"nu-complete claude scopes"   # Comma-separated list of setting sources to load
    --settings: path                                        # Path to a settings JSON file or a JSON string
    --strict-mcp-config                                     # Only use MCP servers from --mcp-config
    --system-prompt: string                                 # System prompt to use for the session
    --tmux                                                  # Create a tmux session for the worktree (requires --worktree)
    --tools: string@"nu-complete claude tools"              # Available tools from the built-in set
    --verbose                                               # Override verbose mode setting from config
    --version(-v)                                           # Output the version number
    --worktree(-w)                                          # Create a new git worktree for this session
    prompt?: string@"nu-complete claude prompt"             # Session id when resuming, otherwise the initial prompt
    ...rest
]

def "nu-complete claude input-format" [] { ["text" "stream-json"] }
def "nu-complete claude output-format" [] { ["text" "json" "stream-json"] }

# Manage background agents
export extern "claude agents" [
    --add-dir: directory                                    # Extra directory allowed in dispatched sessions (repeatable)
    --agent: string@"nu-complete claude agents"             # Default agent for dispatched sessions
    --all                                                   # With --json: also include completed background sessions
    --allow-dangerously-skip-permissions                    # Make bypass-permissions available to dispatched sessions
    --cwd: directory                                        # Show only background sessions started under this path
    --dangerously-skip-permissions                          # Alias for --permission-mode bypassPermissions
    --effort: string@"nu-complete claude effort"            # Default effort level for dispatched sessions
    --help(-h)                                              # Display help for command
    --json                                                  # Print active sessions as a JSON array and exit
    --mcp-config: path                                      # MCP server configuration for dispatched sessions (repeatable)
    --model: string@"nu-complete claude models"             # Default model for dispatched sessions
    --permission-mode: string@"nu-complete claude permission-modes" # Default permission mode for dispatched sessions
    --plugin-dir: directory                                 # Load plugins from a directory for the agent view (repeatable)
    --setting-sources: string@"nu-complete claude scopes"   # Comma-separated list of setting sources to load
    --settings: path                                        # Settings file or JSON string for the agent view
    --strict-mcp-config                                     # Only use MCP servers from --mcp-config in dispatched sessions
    ...rest
]

# Manage authentication
export extern "claude auth" [ --help(-h) ...rest ]

# Sign in to your Anthropic account
export extern "claude auth login" [
    --claudeai              # Use Claude subscription (default)
    --console               # Use Anthropic Console (API usage billing)
    --email: string         # Pre-populate email address on the login page
    --sso                   # Force SSO login flow
    ...rest
]

# Log out from your Anthropic account
export extern "claude auth logout" [ ...rest ]

# Show authentication status
export extern "claude auth status" [
    --json                  # Output as JSON (default)
    --text                  # Output as human-readable text
    ...rest
]

# Inspect or reset auto mode classifier configuration
export extern "claude auto-mode" [ --help(-h) ...rest ]

# Print the effective auto mode config as JSON
export extern "claude auto-mode config" [ ...rest ]

# Get AI feedback on your custom auto mode rules
export extern "claude auto-mode critique" [
    --model: string@"nu-complete claude models"     # Override which model is used
    ...rest
]

# Print the default auto mode rules as JSON
export extern "claude auto-mode defaults" [
    --label: string         # Show only rules whose label starts with this prefix
    ...rest
]

# Reset auto mode configuration to the shipped defaults
export extern "claude auto-mode reset" [
    --yes(-y)               # Skip the confirmation prompt
    ...rest
]

# Check the health of your Claude Code installation
export extern "claude doctor" [ --help(-h) ...rest ]

# Run the enterprise auth/telemetry gateway
export extern "claude gateway" [
    --config: path          # Path to gateway YAML config
    --help(-h)              # Display help for command
    ...rest
]

# Install Claude Code native build
export extern "claude install" [
    --force                 # Force installation even if already installed
    --help(-h)              # Display help for command
    version?: string@"nu-complete claude install-versions"  # Version to install
    ...rest
]

def "nu-complete claude install-versions" [] { ["stable" "latest"] }

# Set up a long-lived authentication token
export extern "claude setup-token" [ --help(-h) ...rest ]

# Run a cloud-hosted multi-agent code review and print findings
export extern "claude ultrareview" [
    --help(-h)              # Display help for command
    --json                  # Print the raw bugs.json payload instead of formatted findings
    --timeout: string       # Maximum minutes to wait for the review to finish (default 30)
    ...rest
]

# Check for updates and install if available
export extern "claude update" [ --help(-h) ...rest ]

# Configure and manage MCP servers
export extern "claude mcp" [ --help(-h) ...rest ]

# Add an MCP server to Claude Code
export extern "claude mcp add" [
    --callback-port: string                                 # Fixed port for the OAuth callback
    --client-id: string                                     # OAuth client ID for HTTP/SSE servers
    --client-secret                                         # Prompt for the OAuth client secret
    --env(-e): string                                       # Set environment variables (KEY=value)
    --header(-H): string                                    # Set headers (Name: value)
    --scope(-s): string@"nu-complete claude scopes"         # Configuration scope (default local)
    --transport(-t): string@"nu-complete claude transports" # Transport type (default stdio)
    ...rest
]

def "nu-complete claude transports" [] { ["stdio" "sse" "http"] }

# Import MCP servers from Claude Desktop (Mac and WSL only)
export extern "claude mcp add-from-claude-desktop" [
    --scope(-s): string@"nu-complete claude scopes"         # Configuration scope (default local)
    ...rest
]

# Add an MCP server with a JSON string
export extern "claude mcp add-json" [
    --client-secret                                         # Prompt for the OAuth client secret
    --scope(-s): string@"nu-complete claude scopes"         # Configuration scope (default local)
    ...rest
]

# Get details about an MCP server
export extern "claude mcp get" [ ...rest ]

# List configured MCP servers
export extern "claude mcp list" [ ...rest ]

# Authenticate with an MCP server
export extern "claude mcp login" [
    --no-browser            # Print the authorization URL instead of opening a browser
    ...rest
]

# Clear stored OAuth credentials for an MCP server
export extern "claude mcp logout" [ ...rest ]

# Remove an MCP server
export extern "claude mcp remove" [
    --scope(-s): string@"nu-complete claude scopes"         # Configuration scope to remove from
    ...rest
]

# Reset approved and rejected project-scoped servers
export extern "claude mcp reset-project-choices" [ ...rest ]

# Start the Claude Code MCP server
export extern "claude mcp serve" [
    --debug(-d)             # Enable debug mode
    --verbose               # Override verbose mode setting from config
    ...rest
]

# Manage Claude Code plugins
export extern "claude plugin" [ --help(-h) ...rest ]

# Show a plugin component inventory and projected token cost
export extern "claude plugin details" [ ...rest ]

# Disable an enabled plugin
export extern "claude plugin disable" [
    --all(-a)                                               # Disable all enabled plugins
    --scope(-s): string@"nu-complete claude scopes"         # Installation scope (default auto-detect)
    ...rest
]

# Enable a disabled plugin
export extern "claude plugin enable" [
    --scope(-s): string@"nu-complete claude scopes"         # Installation scope (default auto-detect)
    ...rest
]

# Run eval cases against a plugin and report scored results
export extern "claude plugin eval" [
    --ablation: string@"nu-complete claude ablation"        # Run a no-plugin baseline arm and report the score delta
    --allow-tools: string@"nu-complete claude tools"        # Operator grant for gated tools
    --case: string                                          # Filter cases by name glob
    --json: path                                            # Print the full run result as JSON, or write it to a .json file
    --judge-model: string@"nu-complete claude models"       # Override the LLM-grader model (default haiku)
    --keep-temp                                             # Preserve scaffold dirs for debugging
    --max-cost-usd: string                                  # Hard cost ceiling; abort and report partial results if hit
    --model: string@"nu-complete claude models"             # Override model for all cases
    --no-scaffold                                           # Explicitly skip scaffold_script
    --output-dir: directory                                 # Directory for aggregate-result.json
    --publish-report                                        # Publish the HTML report privately to claude.ai and print its link
    --report: path                                          # Write a self-contained HTML report to this path
    --runs: string                                          # Override per-case runs (default case.runs or 3)
    --scaffold                                              # Run each case scaffold_script (runs author-supplied bash as you)
    --tag: string                                           # Filter cases by tag (repeatable)
    --threshold: string                                     # Exit 1 if any case score is below this threshold (default 1.0)
    --verbose                                               # Stream the trace as it runs
    ...rest
]

def "nu-complete claude ablation" [] { ["none" "with-without"] }

# Author an eval suite under evals/ via an interview
export extern "claude plugin eval init" [
    --bare                  # Write a blank template instead of running the interview
    ...rest
]

# Scaffold a new plugin under ~/.claude/skills/
export extern "claude plugin init" [
    --author: string                                        # Author name (default git config user.name)
    --author-email: string                                  # Author email (default git config user.email)
    --description: string                                   # Manifest description
    --force(-f)                                             # Overwrite an existing .claude-plugin/ at the target
    --with: string@"nu-complete claude plugin-components"   # Also scaffold these components
    ...rest
]

def "nu-complete claude plugin-components" [] {
    ["skills" "agents" "hooks" "mcp" "lsp" "output-style" "channel"]
}

# Install a plugin from available marketplaces
export extern "claude plugin install" [
    --config: string                                            # Set a userConfig option declared in the manifest (key=value)
    --scope(-s): string@"nu-complete claude install-scopes"     # Installation scope (default user)
    ...rest
]

# List installed plugins
export extern "claude plugin list" [
    --available             # Include available plugins from marketplaces (requires --json)
    --json                  # Output as JSON
    ...rest
]

# Manage Claude Code marketplaces
export extern "claude plugin marketplace" [ ...rest ]

# Add a marketplace from a URL, path, or GitHub repo
export extern "claude plugin marketplace add" [
    --scope: string@"nu-complete claude install-scopes"      # Where to declare the marketplace (default user)
    --sparse: string                                         # Limit checkout to specific directories via git sparse-checkout
    ...rest
]

# List all configured marketplaces
export extern "claude plugin marketplace list" [
    --json                  # Output as JSON
    ...rest
]

# Remove a configured marketplace
export extern "claude plugin marketplace remove" [
    --scope: string@"nu-complete claude install-scopes"      # Settings scope to remove the declaration from
    ...rest
]

# Update marketplace(s) from their source
export extern "claude plugin marketplace update" [ ...rest ]

# Remove auto-installed dependencies that are no longer needed
export extern "claude plugin prune" [
    --dry-run                                                # List what would be removed without removing
    --scope(-s): string@"nu-complete claude install-scopes"  # Prune at scope (default user)
    --yes(-y)                                                # Skip the confirmation prompt
    ...rest
]

# Create a name--vversion git tag for a plugin release
export extern "claude plugin tag" [
    --dry-run               # Print what would be tagged without creating it
    --force(-f)             # Skip the dirty-tree and tag-already-exists checks
    --message(-m): string   # Tag annotation message (use %s for the version)
    --push                  # Push the tag to --remote after creating it
    --remote: string        # Remote to push to with --push (default origin)
    ...rest
]

# Uninstall an installed plugin
export extern "claude plugin uninstall" [
    --keep-data                                              # Preserve the plugin persistent data directory
    --prune                                                  # Also remove auto-installed dependencies no longer needed
    --scope(-s): string@"nu-complete claude install-scopes"  # Uninstall from scope (default user)
    --yes(-y)                                                # Skip the --prune confirmation prompt
    ...rest
]

# Update a plugin to the latest version
export extern "claude plugin update" [
    --scope(-s): string@"nu-complete claude update-scopes"   # Installation scope (default user)
    ...rest
]

# Validate a plugin or marketplace manifest
export extern "claude plugin validate" [
    --strict                # Treat warnings as errors (exit 1)
    manifest?: path         # Plugin or marketplace manifest path
    ...rest
]

# Manage Claude Code project state
export extern "claude project" [ --help(-h) ...rest ]

# Delete all Claude Code state for a project
export extern "claude project purge" [
    --all                   # Purge state for every project
    --dry-run               # List what would be deleted without deleting anything
    --interactive(-i)       # Prompt for each item before deleting
    --yes(-y)               # Skip confirmation prompt
    project?: directory     # Project path
    ...rest
]
