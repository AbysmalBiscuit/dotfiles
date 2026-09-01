# Trash and file-manager wrappers.

# trash-cli writes to $HOME's trash by default, which fails across mount points.
# Pick the trash directory that belongs to the filesystem the cwd sits on.
def trash-dir []: nothing -> path {
    let real_pwd = (^realpath $env.PWD | str trim)
    if (^stat -c %d $env.HOME | str trim) == (^stat -c %d $real_pwd | str trim) {
        [($env.XDG_DATA_HOME? | default ([$env.HOME .local share] | path join)) Trash] | path join
    } else {
        let mountpoint = (^findmnt -n -o TARGET --target $real_pwd | str trim)
        [$mountpoint $".Trash-(^id -u | str trim)"] | path join
    }
}

def --wrapped trash [...args] { ^trash --trash-dir (trash-dir) ...$args }
def --wrapped trash-put [...args] { ^trash-put --trash-dir (trash-dir) ...$args }
def --wrapped trash-list [...args] { ^trash-list --trash-dir (trash-dir) ...$args }
def --wrapped trash-empty [...args] { ^trash-empty --trash-dir (trash-dir) ...$args }
def --wrapped trash-restore [...args] { ^trash-restore --trash-dir (trash-dir) ...$args }

# On WSL, yazi on a Windows drive is far faster as the native Windows build.
def --wrapped wyazi [...args] {
    if (is-wsl) and ($env.PWD | str starts-with "/mnt/") and ($env.YAZI_WINDOWS_EXECUTABLE? | is-not-empty) {
        ^$env.YAZI_WINDOWS_EXECUTABLE ...$args
    } else {
        ^yazi ...$args
    }
}

# Open yazi and cd into wherever it was closed. --env so the cd survives.
def --env --wrapped y [...args] { yazi-cd { |tmp| ^yazi ...$args --cwd-file $tmp } }
def --env --wrapped wy [...args] { yazi-cd { |tmp| wyazi ...$args --cwd-file $tmp } }

def --env yazi-cd [run: closure] {
    let tmp = (^mktemp -t "yazi-cwd.XXXXXX" | str trim)
    do $run $tmp
    let cwd = (open --raw $tmp | str trim)
    ^rm -f $tmp
    if ($cwd | is-not-empty) and $cwd != $env.PWD { cd $cwd }
}

# Activate the cwd's .venv. `python -m venv` writes no activate.nu, so set the
# variables directly rather than depending on one.
def --env venv [] {
    let root = ([$env.PWD .venv] | path join)
    let bin = ([$root bin] | path join)
    if not ($bin | path exists) { error make { msg: $"no virtualenv at ($root)" } }
    if ($env.VIRTUAL_ENV? | is-not-empty) { deactivate }
    $env.VENV_OLD_PATH = $env.PATH
    $env.VIRTUAL_ENV = $root
    $env.PATH = ($env.PATH | prepend $bin)
    hide-env --ignore-errors PYTHONHOME
}

def --env deactivate [] {
    if ($env.VENV_OLD_PATH? | is-not-empty) { $env.PATH = $env.VENV_OLD_PATH }
    hide-env --ignore-errors VIRTUAL_ENV
    hide-env --ignore-errors VENV_OLD_PATH
}
