#!/usr/bin/env pwsh
<#
.SYNOPSIS
Reset the current worktree's branch to exactly match its upstream.

.DESCRIPTION
Fetches, then `git reset --hard @{upstream}`, discarding local commits and
uncommitted changes. Refuses on protected branches and prompts before the
destructive step unless -Yes is given.

PowerShell port of git-reset-pr-branch.sh.

.PARAMETER Directory
Operate in <dir> instead of the current directory. Aliased to -C.

.PARAMETER Yes
Skip the confirmation prompt.

.PARAMETER Clean
Also `git clean -fd` (remove untracked files/dirs) after reset.

.EXAMPLE
git-reset-pr-branch.ps1 -C ..\other-worktree -Yes --Clean
#>
[CmdletBinding()]
param(
    [Alias('C')][string]$Directory = (Get-Location).Path,
    [Alias('y')][switch]$Yes,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$Protected = @('main', 'master', 'staging')

function Die([string]$message) {
    [Console]::Error.WriteLine("error: $message")
    exit 1
}

# All git calls target $Directory so the script never mutates the caller's cwd.
function Invoke-Git {
    git -C $Directory @args
}

Invoke-Git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Die "not inside a git work tree" }

$branch = Invoke-Git symbolic-ref --quiet --short HEAD
if ($LASTEXITCODE -ne 0 -or -not $branch) { Die "detached HEAD - check out a branch first" }

if ($Protected -contains $branch) {
    Die "refusing to hard-reset protected branch '$branch'"
}

# Resolve the upstream this branch tracks (usually origin/<branch>).
$upstream = Invoke-Git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $upstream) {
    Die "branch '$branch' has no upstream - set one with: git branch --set-upstream-to=origin/$branch"
}

$remote = $upstream.Split('/')[0]
Write-Host "Fetching '$remote'..."
Invoke-Git fetch --prune $remote
if ($LASTEXITCODE -ne 0) { Die "fetch from '$remote' failed" }

$before = Invoke-Git rev-parse HEAD
$after = Invoke-Git rev-parse $upstream

function Remove-Untracked {
    Write-Host "Cleaning untracked files..."
    Invoke-Git clean -fd
}

if ($before -eq $after) {
    Write-Host "Already at $upstream ($after). Nothing to reset."
    # Still honour -Clean so the tree can be scrubbed even when refs match.
    if ($Clean) { Remove-Untracked }
    exit 0
}

$ahead = [int](Invoke-Git rev-list --count "$upstream..HEAD")
$behind = [int](Invoke-Git rev-list --count "HEAD..$upstream")

Write-Host ""
Write-Host "Branch '$branch' will be reset to '$upstream'."
Write-Host "  HEAD     $before"
Write-Host "  upstream $after"
Write-Host "  local is $ahead commit(s) ahead, $behind behind upstream"
if ($ahead -gt 0) {
    Write-Host "  $ahead local commit(s) will be discarded (recoverable via git reflog)"
}

Invoke-Git diff --quiet
$dirty = $LASTEXITCODE -ne 0
Invoke-Git diff --cached --quiet
$dirty = $dirty -or ($LASTEXITCODE -ne 0)
if ($dirty) {
    Write-Host "  uncommitted changes present - these WILL be lost"
}

if (-not $Yes) {
    $reply = Read-Host "Proceed with hard reset? [y/N]"
    if ($reply -notmatch '^[Yy]$') { Die "aborted" }
}

Invoke-Git reset --hard $upstream
if ($LASTEXITCODE -ne 0) { Die "reset failed" }

if ($Clean) { Remove-Untracked }

Write-Host "Done. '$branch' now matches '$upstream'."
