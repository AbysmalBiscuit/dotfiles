#Requires -Version 5.1
<#
.SYNOPSIS
Open an alacritree session in each of the given directories, or restore a saved
set of them.

.DESCRIPTION
A directory the sidebar already carries — a worktree root, or anything inside
one — gets its session under that worktree. Anything else opens in the home
workspace and is sent a `cd` to the directory, so a path outside every project
still lands where you asked without touching the sidebar. Nothing is ever added
as a project. Needs a running alacritree.

With no paths (or with -Restore), skim — or fzf, whichever is on PATH — lists
the files written by `alacritree-save-sessions`, newest first, previewing the
paths each one would reopen. Select one or more with Tab.

WSL paths are accepted in three spellings, all resolved against the **default**
distro: a POSIX path (`/home/lev/x`), a `/mnt/<drive>` path (handed back to
Windows as `<Drive>:\x`), and the `\\wsl.localhost\<distro>\…` UNC form. A
session under a WSL worktree runs a Linux shell, so it is sent the POSIX
spelling; a home session runs the configured shell and is sent the Windows one.

The `cd` is typed into the shell, so it assumes a shell that understands
`cd 'path'` (PowerShell, bash, zsh, fish). Its success is not verified.

Emits one object per path (Path, Workspace, Home, SessionId, Error) and exits
non-zero if any path failed.

.EXAMPLE
alacritree-open.ps1 ~/Git/github/alacritree /home/lev/Git/adaptyv/monorepo

.EXAMPLE
alacritree-open.ps1 -Restore

.EXAMPLE
Get-ChildItem -Directory ~/Git/worktrees | alacritree-open.ps1 -Select
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true, ValueFromPipeline = $true)]
    [string[]] $Path,

    # Pick a saved session file to reopen. Implied when no paths are given.
    [switch] $Restore,

    # Fail a directory no project owns instead of opening it in the home workspace.
    [switch] $WorktreesOnly,

    # Focus the workspace of the last session opened.
    [switch] $Select,

    # Talk to the instance on this socket rather than finding one.
    [string] $Socket,

    # Print a saved session file and exit — this is the picker's preview command.
    [string] $ShowFile
)

begin {
    if ($ShowFile) {
        if (Test-Path -LiteralPath $ShowFile) { Get-Content -LiteralPath $ShowFile }
        else { "missing: $ShowFile" }
        exit 0
    }

    $exe = Join-Path $PSScriptRoot 'alacritree.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $found = Get-Command alacritree -CommandType Application -ErrorAction SilentlyContinue
        if (-not $found) { throw 'alacritree is neither next to this script nor on PATH' }
        $exe = $found.Source
    }

    $common = @('--json')
    if ($Socket) { $common += @('--socket', $Socket) }

    $wslUncPattern = '^\\\\wsl(?:\.localhost|\$)\\[^\\]+(\\.*)?$'

    # Mirrors alacritree's own state dir: the roaming app-data dir on Windows,
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

    # Every reply is JSON on stdout and failure is a non-zero exit, so one
    # helper covers both outcomes without the caller parsing anything.
    function Invoke-Alacritree {
        param([string[]] $Arguments)

        $raw = (& $exe @common @Arguments 2>&1 | Out-String)
        $ok = ($LASTEXITCODE -eq 0)
        $obj = $null
        try { $obj = $raw | ConvertFrom-Json } catch { }
        $message = if ($obj -and $obj.PSObject.Properties['error']) { $obj.error } else { $raw.Trim() }

        [pscustomobject]@{ Ok = $ok; Data = $obj; Error = $message }
    }

    # `wsl -e` without -d runs in the default distro, which names itself in
    # $WSL_DISTRO_NAME — locale-independent, unlike parsing `wsl -l` for the
    # translated "(Default)" marker.
    $script:defaultDistro = $null
    function Get-DefaultDistro {
        if ($null -eq $script:defaultDistro) {
            $name = (& wsl.exe -e sh -c 'echo $WSL_DISTRO_NAME' 2>$null | Out-String)
            $script:defaultDistro = $name -replace '[\0\r\n]', ''
        }
        if (-not $script:defaultDistro) { throw 'no default WSL distro (is WSL installed and started?)' }
        $script:defaultDistro
    }

    # A path as Windows spells it: /mnt/<drive> belongs to Windows already,
    # anything else absolute-POSIX lives in the default distro's filesystem.
    function ConvertTo-WindowsPath {
        param([string] $Requested)

        $p = $Requested -replace '^//', '\\'
        if ($p.StartsWith('\\')) { return $p.Replace('/', '\') }

        if ($p -match '^/mnt/([a-zA-Z])(/.*)?$') {
            $rest = if ($Matches[2]) { $Matches[2] } else { '/' }
            return ($Matches[1].ToUpper() + ':' + $rest).Replace('/', '\')
        }
        if ($p.StartsWith('/')) {
            return '\\wsl.localhost\' + (Get-DefaultDistro) + $p.Replace('/', '\')
        }
        $Requested
    }

    # The POSIX spelling of a path inside a distro; $null for a Windows path.
    function ConvertTo-PosixPath {
        param([string] $WindowsPath)

        if ($WindowsPath -notmatch $wslUncPattern) { return $null }
        if (-not $Matches[1]) { return '/' }
        $Matches[1].Replace('\', '/')
    }

    # The worktree a path belongs to: the longest known root it equals or sits
    # under, matching how alacritree resolves an owner itself. `session create`
    # takes only a worktree root, so a path deeper in the tree needs this.
    function Resolve-OwningWorktree {
        param([string] $Directory)

        # The sidebar spells its paths with forward slashes and Resolve-Path
        # with backslashes, so both sides are normalized before comparing.
        $probe = $Directory.Replace('/', '\').TrimEnd('\')
        Get-KnownWorktrees |
            Where-Object {
                $root = $_.path.Replace('/', '\').TrimEnd('\')
                $probe -eq $root -or $probe.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
            } |
            Sort-Object { $_.path.Length } -Descending |
            Select-Object -First 1 -ExpandProperty path
    }

    # Every worktree the sidebar carries, fetched once for the whole run.
    $script:knownWorktrees = $null
    function Get-KnownWorktrees {
        if ($null -eq $script:knownWorktrees) {
            $listed = Invoke-Alacritree @('project', 'list')
            $script:knownWorktrees = if ($listed.Ok) { @($listed.Data.projects.worktrees) } else { @() }
        }
        $script:knownWorktrees
    }

    function Send-ChangeDirectory {
        param([int] $SessionId, [string] $Directory, [switch] $AsPosix)

        if ($AsPosix) {
            $target = ConvertTo-PosixPath $Directory
            $quoted = "'" + $target.Replace("'", "'\''") + "'"
        } else {
            $quoted = "'" + $Directory.Replace("'", "''") + "'"
        }
        Invoke-Alacritree @('session', 'send-text', "$SessionId", "cd $quoted", '--enter')
    }

    # The picker runs from the sessions directory so the list shows bare file
    # names and the preview, which inherits that directory, resolves them.
    function Select-SavedPaths {
        if (-not (Test-Path -LiteralPath $sessionsDir)) {
            throw "no saved sessions yet — run alacritree-save-sessions first ($sessionsDir)"
        }
        $files = @(Get-ChildItem -LiteralPath $sessionsDir -Filter '*.txt' -File | Sort-Object Name -Descending)
        if ($files.Count -eq 0) { throw "no saved sessions in $sessionsDir" }

        $picker = Get-Command sk -CommandType Application -ErrorAction SilentlyContinue
        if (-not $picker) { $picker = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue }
        if (-not $picker) { throw 'neither sk (skim) nor fzf is on PATH' }

        $preview = "pwsh -NoProfile -File `"$PSCommandPath`" -ShowFile {}"
        Push-Location -LiteralPath $sessionsDir
        try {
            $chosen = $files.Name | & $picker.Source `
                --multi `
                --prompt 'restore> ' `
                --header 'Tab selects several, Enter restores' `
                --preview $preview `
                --preview-window 'right:60%'
        } finally {
            Pop-Location
        }

        @($chosen) |
            Where-Object { $_ } |
            ForEach-Object { Get-Content -LiteralPath (Join-Path $sessionsDir $_) } |
            Where-Object { $_.Trim() }
    }

    $targets = [System.Collections.Generic.List[string]]::new()
}

process {
    foreach ($p in $Path) {
        if ($p) { $targets.Add($p) }
    }
}

end {
    if ($Restore -or $targets.Count -eq 0) {
        foreach ($p in Select-SavedPaths) { $targets.Add($p) }
    }
    if ($targets.Count -eq 0) { throw 'nothing to open' }

    $failures = 0
    $lastWorkspace = $null

    foreach ($requested in $targets) {
        $result = [pscustomobject]@{
            Path      = $requested
            Workspace = $null
            Home      = $false
            SessionId = $null
            Error     = $null
        }

        $windows = try { ConvertTo-WindowsPath $requested } catch { $null }
        $dir = if ($windows) {
            try { (Resolve-Path -LiteralPath $windows -ErrorAction Stop).ProviderPath } catch { $null }
        }
        if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) {
            $result.Error = 'not a directory'
            $failures++
            $result
            continue
        }

        $owner = Resolve-OwningWorktree -Directory $dir

        if ($owner) {
            $created = Invoke-Alacritree @('session', 'create', '--workspace', $owner)
            $result.Workspace = $owner
        } elseif ($WorktreesOnly) {
            $result.Error = 'no project in the sidebar owns this directory'
            $failures++
            $result
            continue
        } else {
            $created = Invoke-Alacritree @('session', 'create')
            $result.Home = $true
        }

        if (-not $created.Ok) {
            $result.Error = $created.Error
            $failures++
            $result
            continue
        }

        $result.SessionId = $created.Data.session_id
        $lastWorkspace = if ($owner) { $owner } else { '' }

        # A worktree session already starts at its root; only a home session or
        # a path deeper in the tree has somewhere left to go.
        $startsElsewhere = -not $owner -or
            $owner.Replace('/', '\').TrimEnd('\') -ne $dir.Replace('/', '\').TrimEnd('\')
        if ($startsElsewhere) {
            # A session under a WSL worktree runs a Linux shell; the home
            # workspace runs the configured one, which reads Windows paths.
            $posix = [bool]$owner -and $owner.Replace('/', '\') -match $wslUncPattern
            $sent = Send-ChangeDirectory -SessionId $result.SessionId -Directory $dir -AsPosix:$posix
            if (-not $sent.Ok) { Write-Warning "session $($result.SessionId) opened but cd failed: $($sent.Error)" }
        }

        $result
    }

    if ($Select -and $null -ne $lastWorkspace) {
        $focused = if ($lastWorkspace) {
            Invoke-Alacritree @('workspace', 'select', $lastWorkspace)
        } else {
            Invoke-Alacritree @('workspace', 'select')
        }
        if (-not $focused.Ok) { Write-Warning "could not focus the last workspace: $($focused.Error)" }
    }

    exit $failures
}
