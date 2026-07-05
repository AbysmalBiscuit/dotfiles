#!/usr/bin/env pwsh
# Fuzzy-pick a project directory and open (or switch to) a psmux session named
# after it. One session per project folder, created on demand and reused on
# return. PowerShell port of tmux-sessionizer (bash) for psmux on Windows;
# session persistence comes from psmux-resurrect/continuum rather than tmuxp,
# so there is no per-project workspace file. Bound to `prefix + f` in
# ~/.psmux.conf.
#
# Usage:
#   tmux-sessionizer.ps1            # fuzzy-pick a project
#   tmux-sessionizer.ps1 <dir>      # jump straight to a specific directory
param([string]$Dir)

function Get-Candidates {
    # A "project" is a git repo root. ~/Git mixes <category>/<project> and
    # direct <project> repos, so find .git dirs (any nesting) and strip to the
    # repo root instead of listing every subdirectory.
    $git = Join-Path $HOME 'Git'
    if (Test-Path $git) {
        fd -H -t d -d 3 '^\.git$' $git | ForEach-Object { $_ -replace '[\\/]\.git[\\/]?$', '' }
    }
    # Standalone project roots that don't live under ~/Git.
    foreach ($p in @("$env:LOCALAPPDATA\nvim", "$HOME\.local\share\chezmoi", "$HOME\bin")) {
        if (Test-Path $p) { $p }
    }
}

# Stable, collision-free session name from a path: strip $HOME and a leading
# Git\ segment for brevity, then map path/dot/colon/space chars to underscores.
# Basenames alone collide across roots, which would merge distinct projects.
function Get-SessionName([string]$path) {
    $rel = $path
    if ($rel.StartsWith($HOME)) { $rel = $rel.Substring($HOME.Length).TrimStart('\', '/') }
    $rel = $rel -replace '^Git[\\/]', ''
    return ($rel -replace '[\\/.:\s]', '_')
}

$selected = $Dir
if (-not $selected) {
    $selected = Get-Candidates | Sort-Object -Unique | fzf --prompt='project> ' --height=100% --reverse
}
if (-not $selected) { exit 0 }
$selected = $selected.TrimEnd('\', '/')
$name = Get-SessionName $selected

psmux has-session -t $name 2>$null
if (-not $?) { psmux new-session -ds $name -c $selected }

# Switch when inside psmux (TMUX is set in panes), attach when outside.
if ($env:TMUX) { psmux switch-client -t $name } else { psmux attach-session -t $name }
