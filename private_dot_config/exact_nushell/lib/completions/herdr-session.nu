def "nu-complete herdr-session agents" [] {
    let agents = (do { ^herdr-session new --list-agents } | complete)
    if $agents.exit_code == 0 {
        $agents.stdout | lines | where {|agent| $agent != "" } | append shell
    } else {
        [shell]
    }
}

# Create or join the current workspace
export extern herdr-session [
    --session: string # Named Herdr server session
    --path: directory # Workspace directory
    --label: string # Name for a new workspace
    --no-attach # Prepare without attaching a client
    --help(-h) # Show help
]

# Create or join the current workspace
export extern "herdr-session open" [
    --session: string
    --path: directory
    --label: string
    --no-attach
    --help(-h)
]

# Open a new tab, choosing an installed coding agent when omitted
export extern "herdr-session new" [
    kind?: string@"nu-complete herdr-session agents"
    --list-agents # Print installed agent choices
    --session: string
    --path: directory
    --label: string
    --no-attach
    --help(-h)
    ...agent_args: string # Agent arguments after --
]

# List tabs and agents in the current workspace
export extern "herdr-session list" [
    --json # Print session rows as JSON
    --session: string
    --path: directory
    --help(-h)
]

# Close this workspace and its processes
export extern "herdr-session close" [
    --session: string
    --path: directory
    --help(-h)
]
