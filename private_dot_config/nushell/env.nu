# Nushell environment file. Runs before config.nu.
#
# version = "0.115.0"

def create_left_prompt [] {
    let dir = match (do --ignore-errors { $env.PWD | path relative-to $nu.home-dir }) {
        null => $env.PWD
        '' => '~'
        $relative_pwd => ([~ $relative_pwd] | path join)
    }

    let path_color = (if (is-admin) { ansi red_bold } else { ansi green_bold })
    let separator_color = (if (is-admin) { ansi light_red_bold } else { ansi light_green_bold })
    let path_segment = $"($path_color)($dir)(ansi reset)"

    $path_segment | str replace --all (char path_sep) $"($separator_color)(char path_sep)($path_color)"
}

def create_right_prompt [] {
    # create a right prompt in magenta with green separators and am/pm underlined
    let time_segment = ([
        (ansi reset)
        (ansi magenta)
        (date now | format date '%x %X') # try to respect user's locale
    ] | str join | str replace --regex --all "([/:])" $"(ansi green)${1}(ansi magenta)" |
        str replace --regex --all "([AP]M)" $"(ansi magenta_underline)${1}")

    let last_exit_code = if ($env.LAST_EXIT_CODE != 0) {([
        (ansi rb)
        ($env.LAST_EXIT_CODE)
    ] | str join)
    } else { "" }

    ([$last_exit_code, (char space), $time_segment] | str join)
}

# starship's nu init owns PROMPT_COMMAND, PROMPT_COMMAND_RIGHT, PROMPT_INDICATOR
# and PROMPT_MULTILINE_INDICATOR. The character module lives here rather than in
# starship's `format`, because nushell re-renders only the indicator on a mode
# switch. STARSHIP_SHELL=fish per call: starship honours --keymap only for fish,
# zsh and cmd, so under "nu" every mode reads as insert.
#
# The leading \r\n is the prompt's line break. It cannot live at the end of
# starship's `format`, because nushell strips trailing newlines off external
# command output. \r rather than \n alone: the indicator is emitted verbatim,
# without the \n -> \r\n rewrite render_prompt_left applies.
$env.STARSHIP_CONFIG = ($nu.home-dir | path join ".config" "starship-nu.toml")

$env.PROMPT_INDICATOR_VI_INSERT = {||
  let character = (with-env {STARSHIP_SHELL: "fish"} {
    starship module character --keymap viins --status $env.LAST_EXIT_CODE
  })
  $"\r\n($character)"
}

$env.PROMPT_INDICATOR_VI_NORMAL = {||
  let character = (with-env {STARSHIP_SHELL: "fish"} {
    starship module character --keymap default --status $env.LAST_EXIT_CODE
  })
  $"\r\n($character)"
}

# If you want previously entered commands to have a different prompt from the usual one,
# you can uncomment one or more of the following lines.
# This can be useful if you have a 2-line prompt and it's taking up a lot of space
# because every command entered takes up 2 lines instead of 1. You can then uncomment
# the line below so that previously entered commands show with a single `🚀`.
# $env.TRANSIENT_PROMPT_COMMAND = {|| "🚀 " }
# $env.TRANSIENT_PROMPT_INDICATOR = {|| "" }
# $env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = {|| "" }
# $env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = {|| "" }
# $env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = {|| "" }
# $env.TRANSIENT_PROMPT_COMMAND_RIGHT = {|| "" }

# Specifies how environment variables are:
# - converted from a string to a value on Nushell startup (from_string)
# - converted from a value back to a string when running external commands (to_string)
# Note: The conversions happen *after* config.nu is loaded
$env.ENV_CONVERSIONS = {
    "PATH": {
        from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
        to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
    }
    "Path": {
        from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
        to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
    }
}

$env.NU_CONFIG_DIR = if $nu.os-info.name == "windows" {
  $env.APPDATA | path join 'nushell' 'nupm'
} else {
  $env.HOME | path join '.config' 'nushell'
}

$env.NUPM_HOME = $env.NU_CONFIG_DIR | path join 'nupm'

# sh_env builds the environment on unix and never runs on native Windows, so the
# values lib/*.nu reads have to be resolved here instead. PATH_CLEAN and
# PATH_WINDOWS stay unset on purpose: they only mean something under WSL, and
# every consumer already guards on that.
if $nu.os-info.name == "windows" {
    $env.NVIM_EXECUTABLE = ($env.NVIM_EXECUTABLE? | default (which nvim | get path.0? | default "nvim"))
    $env.PYTHON3_HOST_PROG = ($env.PYTHON3_HOST_PROG? | default (which python | get path.0? | default "python"))
    $env.EDITOR = ($env.EDITOR? | default $env.NVIM_EXECUTABLE)
}

# Directories to search for scripts when calling source or use
# The default for this is $nu.default-config-dir/scripts
$env.NU_LIB_DIRS = [
    ($nu.default-config-dir | path join 'scripts') # add <nushell-config-dir>/scripts
    ($nu.data-dir | path join 'completions') # default home for nushell completions
    ($env.NUPM_HOME | path join "modules")
]

# Directories to search for plugin binaries when calling register
# The default for this is $nu.default-config-dir/plugins
$env.NU_PLUGIN_DIRS = [
    ($nu.default-config-dir | path join 'plugins') # add <nushell-config-dir>/plugins
]

# To add entries to PATH (on Windows you might use Path), you can use the following pattern:
# $env.PATH = ($env.PATH | split row (char esep) | prepend '/some/path')
# An alternate way to add entries to $env.PATH is to use the custom command `path add`
# which is built into the nushell stdlib:
# use std "path add"
# $env.PATH = ($env.PATH | split row (char esep))
# path add /some/path
# path add ($env.CARGO_HOME | path join "bin")
# path add ($env.HOME | path join ".local" "bin")
# $env.PATH = ($env.PATH | uniq)

# To load from a custom file you can use:
# source ($nu.default-config-dir | path join 'custom.nu')

$env.PATH = (
    $env.PATH
        | split row (char esep)
        | prepend ($env.NUPM_HOME | path join "scripts")
        | uniq
)


mkdir $nu.cache-dir

# Completions load from the autoload directories, not from a `source` here.
# Nushell reads every .nu file in $nu.user-autoload-dirs and
# $nu.vendor-autoload-dirs after config.nu, and silently skips a directory that
# does not exist. That is the "only if present" behaviour: chezmoi drops the
# generated scripts in, and a machine where it has not run yet just starts
# without them instead of failing to parse.
#
#   ~/.config/nushell/autoload/          chezmoi's target, user-owned
#   ~/.local/share/nushell/vendor/autoload/   machine-local, chezmoi-free
#
# Regenerate by hand after a tool upgrade, then let chezmoi re-add it:
#   carapace _carapace nushell | save -f ~/.config/nushell/autoload/carapace.nu
#   jj util completion nushell | save -f ~/.config/nushell/autoload/jj.nu
mkdir ($nu.user-autoload-dirs | first)

# Shell integrations, as opposed to completions. Cheap to produce and they must
# exist for the prompt to render at all, so these stay self-healing rather than
# waiting on chezmoi.
const AUTOLOAD = ($nu.data-dir | path join "vendor" "autoload")
mkdir $AUTOLOAD

def regen [bin: string, out: path, gen: closure] {
    if (which $bin | is-empty) { return }
    if ($out | path exists) and ((ls $out | get 0.modified) > (ls (which $bin | get path.0) | get 0.modified)) { return }
    do $gen | save --force $out
}

regen starship ($AUTOLOAD | path join "starship.nu") {|| ^starship init nu }
regen zoxide ($AUTOLOAD | path join "zoxide.nu") {|| ^zoxide init nushell }

# carapace bridges to these shells for any command it does not cover itself,
# which is what keeps the hand-written ~/.config/fish/completions working here.
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
