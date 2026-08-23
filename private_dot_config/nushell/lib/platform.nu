# OS detection, clipboard and the WSL/Windows interop wrappers.

# "wsl" | "linux" | "windows" | "darwin" | "unknown"
def get-os []: nothing -> string {
    match $nu.os-info.name {
        "windows" => "windows"
        "macos" => "darwin"
        "linux" => {
            # WSL_DISTRO_NAME is absent in sessions WSL's init never touched, so
            # the kernel release is the fallback: WSL2 always stamps it
            # "microsoft".
            let wsl = ($env.WSL_DISTRO_NAME? | is-not-empty) or ((open --raw /proc/sys/kernel/osrelease) =~ "(?i)microsoft")
            if $wsl { "wsl" } else { "linux" }
        }
        _ => "unknown"
    }
}

def is-wsl []: nothing -> bool { (get-os) == "wsl" }

# Read the system clipboard. Equivalent to ctrl+V.
def get-clipboard []: nothing -> string {
    match (get-os) {
        "wsl" => (^powershell.exe -command "Get-Clipboard" | str replace --all "\r" "")
        "windows" => (^powershell -NoProfile -Command "Get-Clipboard" | str replace --all "\r" "")
        "linux" => (^xclip -o -selection c)
        "darwin" => (^pbpaste)
        _ => { error make { msg: "no clipboard reader known for this OS" } }
    }
}

# Write to the system clipboard, from an argument or from stdin. Equivalent to ctrl+C.
def set-clipboard [...text: string]: any -> nothing {
    let data = if ($text | is-not-empty) { $text | str join " " } else { $in | into string }
    match (get-os) {
        "wsl" => ($data | ^unix2dos | ^clip.exe)
        "windows" => ($data | ^clip)
        "linux" => ($data | ^xclip -selection c)
        "darwin" => ($data | ^pbcopy)
        _ => { error make { msg: "no clipboard writer known for this OS" } }
    }
}

# Copy a file's contents, the given arguments, or piped input.
def copy [...args: string]: any -> nothing {
    let piped = $in
    if ($args | length) == 1 and ($args.0 | path exists) and (($args.0 | path type) == "file") {
        open --raw $args.0 | set-clipboard
    } else if ($args | is-not-empty) {
        set-clipboard ...$args
    } else {
        $piped | set-clipboard
    }
}

def paste []: nothing -> string { get-clipboard }

# Resolve a Windows environment variable from inside WSL.
def wslvar [...args: string]: nothing -> string {
    ^bash ~/.config/fish/tools/wslvar.sh ...$args
}

# Create a Windows symlink (-s) or shortcut from WSL paths.
def wln [source: path, target: path, --symbolic (-s)] {
    let from = (^wslpath -w $source)
    let to = (^wslpath -w $target)
    if $symbolic {
        let flag = if ($source | path type) == "dir" { "/D " } else { "" }
        ^cmd.exe /C $"mklink ($flag)($to) ($from)"
    } else {
        let win_home = (^wslpath -u (wslvar USERPROFILE))
        let script = (^wslpath -w ([$win_home bin wln.ps1] | path join))
        let lnk = if ($to =~ '(?i)\.(lnk|url)$') { $to } else { $"($to).lnk" }
        ^powershell.exe $script $from $lnk
    }
}

# Open a path (default cwd) in the platform file explorer.
def exp [dir?: path] {
    let target = ($dir | default $env.PWD)
    match (get-os) {
        "wsl" => (^env $"PATH=($env.PATH_WINDOWS)" explorer.exe (^wslpath -w $target))
        # explorer.exe exits 1 even when it did open the window.
        "windows" => (do --ignore-errors { ^explorer $target } | ignore)
        "darwin" => (^open $target)
        _ => (^xdg-open $target)
    }
}

# Duplicate finder. On WSL the Windows build gets the Windows-side paths.
def krokiet [...paths: path] {
    let targets = if ($paths | is-empty) { [$env.PWD] } else { $paths }
    if (is-wsl) {
        ^env $"PATH=($env.PATH_WINDOWS)" krokiet.exe ...($targets | each {|p| ^wslpath -w $p })
    } else {
        ^krokiet ...$targets
    }
}

# alacritree writes escape sequences that only render correctly through a pager-less cat.
def --wrapped alacritree [...args] {
    let bin = ($env.ALACRITREE_EXE? | default (which alacritree.exe | get path.0? ))
    if ($bin | is-empty) {
        error make { msg: "alacritree: alacritree.exe not found in PATH" }
    }
    ^$bin ...$args | ^cat
}

# An interactive bash sub-shell, marked so rc files can detect it.
def --wrapped forcesh [...args] { ^env FORCESH=1 bash ...$args }
