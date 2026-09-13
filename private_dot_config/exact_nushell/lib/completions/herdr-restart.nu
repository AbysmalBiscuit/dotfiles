# Stop the Herdr server and start a fresh one in its place
export extern herdr-restart [
    --session: string # Named Herdr server session
    --manifests(-m) # Fetch the latest agent detection manifests first
    --help(-h) # Show help
]
