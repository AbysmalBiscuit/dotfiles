#Requires -Version 5.1
<#
.SYNOPSIS
Save the workspace of every open alacritree shell session to a text file.

.DESCRIPTION
Writes one path per line, in session order and keeping duplicates, so restoring
reopens the same number of sessions per worktree. The file lands in
`<state dir>\sessions` under a `yyyy-MM-dd_HHmmss` name, which sorts newest-last
lexicographically; `alacritree-open -Restore` picks one back up.

Home-workspace sessions are skipped: alacritree reports no path for them, so
there is nothing to restore them to. Diff and scratchpad panes are skipped for
the same reason.

.EXAMPLE
alacritree-save-sessions.ps1

.EXAMPLE
alacritree-save-sessions.ps1 -Name before-rebase
#>
[CmdletBinding()]
param(
    # Appended to the timestamp, keeping the file sortable by time.
    [string] $Name,

    # Talk to the instance on this socket rather than finding one.
    [string] $Socket
)

$exe = Join-Path $PSScriptRoot 'alacritree.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    $found = Get-Command alacritree -CommandType Application -ErrorAction SilentlyContinue
    if (-not $found) { throw 'alacritree is neither next to this script nor on PATH' }
    $exe = $found.Source
}

$arguments = @('--json')
if ($Socket) { $arguments += @('--socket', $Socket) }
$arguments += @('session', 'list')

$raw = (& $exe @arguments 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "alacritree session list failed: $($raw.Trim())" }
$listed = $raw | ConvertFrom-Json

$shells = @($listed.sessions | Where-Object { $_.kind -eq 'shell' })
$paths = @($shells | Where-Object { $_.workspace } | ForEach-Object { $_.workspace })
$skipped = $shells.Count - $paths.Count

if ($paths.Count -eq 0) { throw 'no shell session has a workspace to save' }

# Mirrors alacritree's own state_dir: the roaming app-data dir on Windows,
# which ignores XDG there, and XDG only on unix.
$onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
$configBase =
    if ($onWindows) {
        if ($env:APPDATA) { $env:APPDATA } elseif ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $HOME }
    } elseif ($env:XDG_CONFIG_HOME) {
        $env:XDG_CONFIG_HOME
    } else {
        Join-Path $HOME '.config'
    }

$sessionsDir = Join-Path (Join-Path $configBase 'alacritree') 'sessions'
if (-not (Test-Path -LiteralPath $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
}

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$leaf = if ($Name) { "$stamp-$($Name -replace '[^\w.-]', '-').txt" } else { "$stamp.txt" }
$file = Join-Path $sessionsDir $leaf

Set-Content -LiteralPath $file -Value $paths -Encoding UTF8

if ($skipped -gt 0) {
    Write-Warning "$skipped session(s) in the home workspace have no path and were skipped"
}
Write-Verbose "saved $($paths.Count) path(s)"
$file
