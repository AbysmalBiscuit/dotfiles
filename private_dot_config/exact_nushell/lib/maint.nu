# Update scripts and small interactive tools.

if $nu.os-info.name == "windows" {
    def --wrapped "codex update" [...args: string] {
        ^pwsh -NoProfile -ExecutionPolicy Bypass -Command '$env:CODEX_NON_INTERACTIVE=1; irm https://chatgpt.com/codex/install.ps1 | iex'
    }
}

def update-claude-plugins [] {
    ^claude plugin marketplace update
    ^claude plugin list --json | from json | get id | each {|id| ^claude plugin update $id }
    null
}

# Repeatedly evaluate arithmetic. Nushell evaluates expressions natively, so
# each line is handed to a bare `nu` rather than to a separate math language.
def math-prompt [] {
    loop {
        let line = input "[math]$ " | str trim
        if $line in ["" "q" "quit" "exit"] { break }
        do --ignore-errors { ^nu -n -c $line }
    }
}

def --wrapped find_float [...args] {
    ^python3 ~/.config/fish/tools/find_float.py ...$args
}

def --wrapped wslvar-sh [...args] { ^bash ~/.config/fish/tools/wslvar.sh ...$args }
