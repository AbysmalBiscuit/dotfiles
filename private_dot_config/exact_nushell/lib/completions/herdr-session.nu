def "nu-complete herdr-session agents" [] {
    let agents = (do { ^herdr-session new --list-agents } | complete)
    if $agents.exit_code == 0 {
        $agents.stdout | lines | where {|agent| $agent != "" } | append shell
    } else {
        [shell]
    }
}

def "nu-complete herdr-session machines" [] {
    let machines = (do { ^herdr machine list --json } | complete)
    if $machines.exit_code == 0 {
        $machines.stdout | from json | where enabled | each {|m| {value: $m.label, description: $m.target} }
    } else {
        []
    }
}

# Create or join the current workspace
export extern herdr-session [
    --session: string # Named Herdr server session
    --machine: string@"nu-complete herdr-session machines" # Saved SSH machine
    --path: directory # Workspace directory
    --label: string # Name for a new workspace
    --no-attach # Leave Alacritree on its current session
    --no-focus # Open in Alacritree without switching to it
    --help(-h) # Show help
]

# Create or join the current workspace
export extern "herdr-session open" [
    --session: string
    --machine: string@"nu-complete herdr-session machines"
    --path: directory
    --label: string
    --no-attach
    --no-focus
    --help(-h)
]

# Open a new tab, choosing an installed coding agent when omitted
export extern "herdr-session new" [
    kind?: string@"nu-complete herdr-session agents"
    --list-agents # Print installed agent choices
    --session: string
    --machine: string@"nu-complete herdr-session machines"
    --path: directory
    --label: string
    --no-attach
    --no-focus
    --help(-h)
    ...agent_args: string # Agent arguments after --
]

# List tabs and agents in the current workspace
export extern "herdr-session list" [
    --json # Print session rows as JSON
    --session: string
    --machine: string@"nu-complete herdr-session machines"
    --path: directory
    --help(-h)
]

# Close this workspace and its processes
export extern "herdr-session close" [
    --session: string
    --machine: string@"nu-complete herdr-session machines"
    --path: directory
    --help(-h)
]
