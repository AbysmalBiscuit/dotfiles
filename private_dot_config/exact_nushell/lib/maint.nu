# Update scripts and small interactive tools.

def update-claude-plugins [] {
    ^claude plugin marketplace update
    ^claude plugin list --json | from json | get id | each {|id| ^claude plugin update $id }
    null
}

# Build and install fish from source with the release rustflags.
def update-fish [] {
    let repo = ([($env.XDG_CACHE_HOME? | default ([$env.HOME .cache] | path join)) fish_shell_repo] | path join)
    mkdir $repo
    if ([$repo .git] | path join | path exists) {
        ^git -C $repo pull
    } else {
        ^git clone https://github.com/fish-shell/fish-shell $repo
    }
    for stale in [build target] {
        let dir = ([$repo $stale] | path join)
        if ($dir | path exists) { rm -rf $dir }
    }
    with-env { RUSTFLAGS: ($env.RUSTFLAGS_RELEASE? | default "") } { ^cargo install --path $repo }
}

# Replace ~/.local/bin/nvim with the current nightly appimage, extracted so the
# appimage's own FUSE mount is never needed.
def update-nvim [] {
    if (get-os) not-in ["wsl" "linux"] { error make { msg: $"update-nvim does not support (get-os)" } }
    let bin_dir = ([$env.HOME .local bin] | path join)
    mkdir $bin_dir

    let stray = ([$bin_dir squashfs-root] | path join)
    if ($stray | path exists) {
        if ([$stray usr bin nvim] | path join | path exists) {
            rm -rf $stray
        } else {
            error make { msg: $"($stray) already exists and is not an extracted neovim; check it manually" }
        }
    }

    let arch = (^uname -m | str trim)
    let asset = $"nvim-linux-($arch).appimage"
    let appimage = ([$bin_dir nvim.appimage] | path join)

    print "Downloading neovim appimage"
    ^wget -O $appimage $"https://github.com/neovim/neovim/releases/download/nightly/($asset)"

    let expected = (do --ignore-errors {
        ^curl -s https://api.github.com/repos/neovim/neovim/releases/tags/nightly
            | from json | get assets | where name == $asset | get 0.digest?
            | default "" | str replace "sha256:" ""
    } | default "")

    if ($expected | is-empty) {
        print "Warning: no checksum published, proceeding with update"
    } else {
        print "Verifying checksum"
        let actual = (open --raw $appimage | hash sha256)
        if $expected != $actual {
            error make { msg: $"checksum mismatch: published ($expected), downloaded ($actual)" }
        }
        print "Checksums match"
    }

    chmod u+x $appimage
    let root = ([$bin_dir nvim-squashfs-root] | path join)
    if ($root | path exists) { rm -rf $root }
    cd $bin_dir
    ^$appimage --appimage-extract
    ^mv $stray $root
    rm -f $appimage ([$bin_dir nvim] | path join)
    ^ln -s ([$root usr bin nvim] | path join) ([$bin_dir nvim] | path join)
    ^chmod -R go-rwx ([$bin_dir nvim] | path join) $root
}

# Repeatedly evaluate arithmetic. Nushell evaluates expressions natively, so
# each line is handed to a bare `nu` rather than to a separate math language.
def math-prompt [] {
    loop {
        let line = (input "[math]$ " | str trim)
        if $line in ["" "q" "quit" "exit"] { break }
        do --ignore-errors { ^nu -n -c $line }
    }
}

def --wrapped find_float [...args] {
    ^python3 ~/.config/fish/tools/find_float.py ...$args
}

def --wrapped wslvar-sh [...args] { ^bash ~/.config/fish/tools/wslvar.sh ...$args }
