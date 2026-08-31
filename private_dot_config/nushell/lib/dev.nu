# Toolchain wrappers: cargo, neovim, gpg, chezmoi, bash interop.

# cargo with release-grade codegen flags. The flag parsing, RUSTFLAGS assembly
# and nightly check all live in ocargo.py so every shell shares one implementation.
def --wrapped ocargo [...args] {
    ^python3 ~/.local/bin/ocargo.py ...$args
}

# neovim. On WSL, `nvim` drops the /mnt/c entries from PATH so Windows binaries
# do not shadow the Linux toolchain that plugins shell out to; `nnvim` keeps the
# full PATH. PATH_CLEAN and NVIM_EXECUTABLE both come from sh_env, which never
# runs on native Windows, so each has a fallback.
def nvim-exe []: nothing -> string { $env.NVIM_EXECUTABLE? | default "nvim" }
def --wrapped nvim [...args] {
    let exe = (nvim-exe)
    if ($env.PATH_CLEAN? | is-empty) {
        ^$exe ...$args
    } else {
        with-env { PATH: ($env.PATH_CLEAN | split row (char esep)) } { ^$exe ...$args }
    }
}
def --wrapped nnvim [...args] { let exe = (nvim-exe); ^$exe ...$args }
def --wrapped nvimtheme [...args] { with-env { RECOMPILE_COLORSCHEME: "true" } { nvim ...$args } }
def --wrapped neovide [...args] {
    if ($env.WSL_DISTRO_NAME? | is-not-empty) { ^neovide.exe --wsl ...$args } else { ^neovide ...$args }
}
def update-nvim-plugins [] { let exe = (nvim-exe); ^$exe --headless "+Lazy! sync" "+qa!" }

def cmsecrets [] { ^bash ([(^chezmoi source-path | str trim) edit_secrets.sh] | path join) }

def superpowers-flow [] {
    if (which claude | is-not-empty) { ^$env.PYTHON3_HOST_PROG ~/.claude/superpowers-flow.py }
}

# Warm the gpg-agent passphrase cache so commit signing does not prompt mid-rebase.
def unlockgpg [] {
    # WSL: gpg-agent reads the passphrase from gnome-keyring via libsecret, so
    # the keyring has to be unlocked first.
    if ($env.WSL_DISTRO_NAME? | is-not-empty) {
        if (which secret-tool | is-empty) {
            print --stderr "secret-tool is needed to unlock the keyring via the terminal."
            print --stderr "Install it with: sudo apt install libsecret-tools"
            return
        }
        ^secret-tool store --label=Unlock unlock true
    }

    # Use the gpg binary and key git is configured with, so this warms the same
    # agent and key that signs commits rather than whatever bare `gpg` resolves to.
    let gpg = (do --ignore-errors { ^git config --get gpg.program } | default "gpg" | str trim)
    let key = (do --ignore-errors { ^git config --get user.signingkey } | default "" | str trim)
    let result = if ($key | is-empty) {
        do --ignore-errors { "warm" | ^$gpg --clearsign | ignore }
    } else {
        do --ignore-errors { "warm" | ^$gpg --local-user $key --clearsign | ignore }
    }
    if $env.LAST_EXIT_CODE == 0 { print "GPG passphrase cached." } else { print --stderr "gpg sign test failed."; error make { msg: "gpg sign test failed" } }
}

# Highest GOAMD64 microarchitecture level this CPU actually runs.
def get-max-go-level []: nothing -> int {
    let probe = (mktemp --suffix .go)
    "package main\nfunc main() {}\n" | save --force --raw $probe
    mut best = 1
    for level in [4 3 2 1] {
        let ok = (do --ignore-errors { ^env GO111MODULE=off $"GOAMD64=v($level)" go run $probe } | complete)
        if $ok.exit_code == 0 { $best = $level; break }
    }
    ^rm -f $probe
    $best
}

def pacmanq [pattern: string] { ^pacman -Q | ^grep $pattern }

# Import the environment a bash command leaves behind, the way fish's bass does.
# Needed for nvm and other tools that only ship a bash activation script.
const BASS_SKIP = [_ PWD OLDPWD SHLVL SHELL BASH BASH_EXECUTION_STRING BASHOPTS SHELLOPTS PS1 PS2]

def --env bass [...cmd: string] {
    let script = ($cmd | str join " ")
    let dumped = (^bash -c $"($script) > /dev/null; env -0" | split row (char null))
    for entry in $dumped {
        let idx = ($entry | str index-of "=")
        if $idx < 1 { continue }
        let key = ($entry | str substring 0..<$idx)
        if $key in $BASS_SKIP { continue }
        let value = ($entry | str substring ($idx + 1)..)
        if $key == "PATH" {
            $env.PATH = ($value | split row (char esep))
        } else {
            load-env { $key: $value }
        }
    }
}

# help2comp emits fish `complete` directives, so it stays a fish call. carapace's
# fish bridge picks the generated files up, which is why porting the emitter
# itself would buy nothing.
def --wrapped help2comp [...args] { ^fish -c $"help2comp ($args | each {|a| $a | to nuon } | str join ' ')" }
def --wrapped help2comp_rec [...args] { ^fish -c $"help2comp_rec ($args | each {|a| $a | to nuon } | str join ' ')" }
