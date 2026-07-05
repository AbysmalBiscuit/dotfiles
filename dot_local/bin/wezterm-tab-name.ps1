#!/usr/bin/env pwsh
# Set the title of the focused WezTerm tab, for grouping psmux windows into
# named "projects". WezTerm's tab_title() (see ~/.wezterm.lua) shows an
# explicitly-set tab title verbatim and otherwise falls back to the psmux
# window's cwd; this script drives that override. PowerShell port of
# wezterm-tab-name (bash) for native Windows.
#
#   custom   -> a name you type; the tab keeps it until changed.
#   static   -> freeze the current cwd basename ($HOME as ~) as the name.
#   dynamic  -> clear the override; the tab follows the active pane's cwd
#               again (the default).
#
# The target is the GUI-focused tab (list-clients -> focused_pane_id -> its
# tab), i.e. whichever tab you are looking at when you run this.
#
# Usage:
#   wezterm-tab-name.ps1                 # interactive menu
#   wezterm-tab-name.ps1 <name>          # set a custom name
#   wezterm-tab-name.ps1 -c | --cwd      # freeze the current cwd basename
#   wezterm-tab-name.ps1 -d | --dynamic  # clear; follow cwd again
param([string]$Name)

# Resolve wezterm: PATH first, then the default Windows install location.
$wt = (Get-Command wezterm -ErrorAction SilentlyContinue).Source
if (-not $wt) { $wt = 'C:\Program Files\WezTerm\wezterm.exe' }
if (-not (Test-Path $wt)) {
    Write-Error 'wezterm-tab-name: wezterm.exe not found'
    exit 1
}

function Get-CwdName {  # basename of $PWD, or ~ for $HOME
    $cwd = (Get-Location).Path
    if ($cwd -eq $HOME) { '~' } else { Split-Path -Leaf $cwd }
}

# The tab the user is looking at: the focused pane's tab.
$clients = & $wt cli list-clients --format json 2>$null | ConvertFrom-Json
$focusedPane = ($clients | Where-Object { $null -ne $_.focused_pane_id } | Select-Object -First 1).focused_pane_id
if ($null -eq $focusedPane) {
    Write-Error 'wezterm-tab-name: could not find the focused WezTerm pane'
    exit 1
}
$tabId = (& $wt cli list --format json 2>$null | ConvertFrom-Json |
    Where-Object { $_.pane_id -eq $focusedPane } | Select-Object -First 1).tab_id
if ($null -eq $tabId) {
    Write-Error "wezterm-tab-name: could not resolve the tab for pane $focusedPane"
    exit 1
}

function Set-Title([string]$title) {  # "" clears the override
    & $wt cli set-tab-title --tab-id $tabId $title
}

# Non-interactive forms.
switch ($Name) {
    { $_ -in '-d', '--dynamic' } { Set-Title ''; "tab $tabId -> dynamic (follows cwd)"; exit 0 }
    { $_ -in '-c', '--cwd' }     { $n = Get-CwdName; Set-Title $n; "tab $tabId -> $n"; exit 0 }
    { $_ -in '-h', '--help' }    { Get-Content $PSCommandPath | Select-Object -Skip 1 -First 19; exit 0 }
    { $_ }                       { Set-Title $Name; "tab $tabId -> $Name"; exit 0 }
}

# Interactive menu.
$cwd = Get-CwdName
Write-Host "Name WezTerm tab ${tabId}:"
Write-Host '  1) custom name'
Write-Host "  2) static cwd ($cwd)"
Write-Host '  3) dynamic (follow cwd)'
$choice = Read-Host 'choice [1]'
switch ($choice) {
    '2' { Set-Title $cwd; "tab $tabId -> $cwd" }
    '3' { Set-Title ''; "tab $tabId -> dynamic (follows cwd)" }
    default {
        $n = Read-Host 'name'
        if (-not $n) { Write-Error 'wezterm-tab-name: empty name, nothing changed'; exit 1 }
        Set-Title $n
        "tab $tabId -> $n"
    }
}
