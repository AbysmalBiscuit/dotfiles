#!/usr/bin/env pwsh
# Rename the current psmux window to #<pr>[<LINEAR-ID>] for the worktree in $Dir.
# PowerShell port of tmux-issue-name (bash) for psmux on Windows.
#
# Prefers devkit's `issue info` when available: it owns the id-from-branch rule,
# the PR lookup, and a per-worktree PR cache. Falls back to local git/gh parsing
# when the `issue` binary is absent.
#
#   id derives from the branch; no id (e.g. `main`, or any repo that isn't an
#     issue worktree) -> name the window after the cwd's basename, the same as
#     outside a git work tree.
#   PR known -> #<pr>[<id>]; otherwise just [<id>].
#   cwd basename is shown with $HOME as ~.
param([string]$Dir = (Get-Location).Path)

if (-not $env:TMUX) { exit 0 }

# Name the window after the cwd: its basename, or ~ for $HOME. This is the
# fallback whenever there is no issue id to name the window after.
function Rename-ToCwd([string]$d) {
    $n = if ($d -eq $HOME) { '~' } else { Split-Path -Leaf $d }
    psmux rename-window $n
}

git -C $Dir rev-parse --is-inside-work-tree 2>$null | Out-Null
if (-not $?) { Rename-ToCwd $Dir; exit 0 }

# Build "#<pr>[<id>]" / "[<id>]" from an id and an optional pr. An empty or
# unknown id is the "no issue" signal: return $null so the caller falls back
# to cwd naming.
function Get-WindowName($id, $pr) {
    if (-not $id -or $id -in @('UNKNOWN', 'null')) { return $null }
    if ($pr -and "$pr" -ne 'null') { return "#$pr[$id]" }
    return "[$id]"
}

if (Get-Command issue -ErrorAction SilentlyContinue) {
    # Fast render from the cache (no network): id always resolves, PR shows if
    # already cached.
    $info = issue info --json --cache-only -C $Dir 2>$null | ConvertFrom-Json
    $name = Get-WindowName $info.issue_id $info.pr_number
    if ($name) { psmux rename-window $name } else { Rename-ToCwd $Dir }
    # id known but PR not yet cached: one full lookup warms the cache and
    # re-renders with the PR. This is the only path that hits the network, and
    # only until the PR is cached.
    if ($info.issue_id -and $info.issue_id -ne 'UNKNOWN' -and -not $info.pr_number) {
        $info = issue info --json -C $Dir 2>$null | ConvertFrom-Json
        $name = Get-WindowName $info.issue_id $info.pr_number
        if ($name) { psmux rename-window $name }
    }
    exit 0
}

# Fallback (no `issue` binary): derive the id from the branch and look up the
# PR via gh, caching positive results forever (keyed by branch).
$branch = git -C $Dir symbolic-ref --quiet --short HEAD 2>$null
$id = if ("$branch" -match '(?i)[a-z]+-[0-9]+') { $Matches[0].ToUpper() }
# No branch (detached HEAD) or no id in it (e.g. `main`): track cwd.
if (-not $id) { Rename-ToCwd $Dir; exit 0 }

$cacheDir = Join-Path ($env:XDG_CACHE_HOME ?? (Join-Path $HOME '.cache')) 'tmux-issue-name'
$cacheFile = Join-Path $cacheDir ($branch -replace '[/\\]', '_')

if ((Test-Path $cacheFile) -and (Get-Item $cacheFile).Length -gt 0) {
    $pr = (Get-Content $cacheFile -Raw).Trim()
} else {
    Push-Location $Dir
    $pr = gh pr view --json number --jq .number 2>$null
    Pop-Location
    if ($pr) {
        New-Item -ItemType Directory -Force $cacheDir | Out-Null
        Set-Content -Path $cacheFile -Value $pr -NoNewline
    }
}

$name = if ($pr) { "#$pr[$id]" } else { "[$id]" }
psmux rename-window $name
