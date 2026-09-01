# Nushell configuration.
#
# version = "0.115.0"
#
# Only deltas from the built-in defaults live here. As of 0.115 the shipped
# default_config.nu is `$env.config = {}` and every default is defined in Rust,
# so anything not set below tracks upstream instead of freezing at the version
# this file was written against. Run `config nu --default` to see the defaults.

source ./lib/theme.nu

$env.config = {
    color_config: $abc_theme

    edit_mode: vi
    cursor_shape: {
        emacs: blink_block
        vi_insert: blink_line
        vi_normal: blink_block
    }
    buffer_editor: $env.EDITOR?

    # Colours drive both the syntax highlighter and the inline history hint:
    # `false` here silently disables both (nu-cli/src/repl.rs).
    use_ansi_coloring: "auto"
    show_hints: true

    # Kitty keyboard protocol: needed to distinguish ctrl+shift bindings below.
    use_kitty_protocol: true
    # Colour external commands differently once `which` has resolved them.
    highlight_resolved_externals: true

    ls: { clickable_links: true }
    table: { index_mode: always }

    completions: {
        # fuzzy is the closest match to fish's completion pager, which falls
        # through prefix -> substring -> subsequence.
        algorithm: "fuzzy"
        sort: "smart"
    }

    # fish shows a session the commands it ran plus everything on disk from
    # before it started, and never the live typing of a sibling terminal.
    # `isolation` is the same rule: reedline filters on
    # `session_id = :session OR start_timestamp < :session_start`. It is
    # sqlite-only, and nushell rejects the pair at startup under plaintext.
    #
    # No `sync_on_enter`: it re-reads the history file on every prompt, which
    # is what pulls a sibling shell's commands in, and the sqlite backend
    # ignores it anyway (reedline SqliteBackedHistory::sync is a no-op).
    history: {
        max_size: 100_000
        file_format: "sqlite"
        isolation: true
    }

    explore: {
        status_bar_background: { fg: "#1D1F21", bg: "#C4C9C6" }
        command_bar_text: { fg: "#C4C9C6" }
        highlight: { fg: "black", bg: "yellow" }
        status: {
            error: { fg: "white", bg: "red" }
            warn: {}
            info: {}
        }
        selected_cell: { bg: light_blue }
    }

    hooks: {
        display_output: "if (term size).columns >= 100 { table -e } else { table }"
    }

    # Additions only. Menu bindings (tab, ctrl+space, ctrl+r, f1, ...) and the
    # base emacs/vi maps are built in; re-listing them here is what made the old
    # config 1000 lines long.
    keybindings: [
        # fish binds ctrl+e to edit_command_buffer. ctrl+o still works too.
        {
            name: open_command_editor
            modifier: control
            keycode: char_e
            mode: [emacs vi_normal vi_insert]
            event: { send: openeditor }
        }
        # fish's accept-autosuggestion. reedline's vi insert map does not bind
        # the hint completion the way its emacs map does. A hint and a menu never
        # coexist, so fall through to the menu: reedline has no dedicated "accept
        # item" event, `menunext` splices the highlighted value into the buffer
        # and closes the menu outright when it is the only match.
        {
            name: accept_hint
            modifier: control
            keycode: char_f
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: historyhintcomplete }
                    { send: menunext }
                ]
            }
        }
        {
            name: accept_hint_right
            modifier: none
            keycode: right
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: historyhintcomplete }
                    { send: menuright }
                    { send: right }
                ]
            }
        }
        {
            name: accept_hint_end
            modifier: none
            keycode: end
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: historyhintcomplete }
                    { edit: movetolineend }
                ]
            }
        }
        # fish's forward-word on an autosuggestion: take one word at a time.
        {
            name: accept_hint_word
            modifier: alt
            keycode: char_f
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: historyhintwordcomplete }
                    { edit: movewordright }
                ]
            }
        }
        {
            name: accept_hint_word_arrow
            modifier: control
            keycode: right
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: historyhintwordcomplete }
                    { edit: movewordright }
                ]
            }
        }
        {
            name: select_all
            modifier: control_shift
            keycode: char_a
            mode: [emacs vi_normal vi_insert]
            event: { edit: selectall }
        }
        {
            name: cut_selection
            modifier: control_shift
            keycode: char_x
            mode: [emacs vi_normal vi_insert]
            event: { edit: cutselection }
        }
    ]
}

# Two fixes applied to every menu, since menus are a list and there is no way to
# set a default for all of them.
#
# The marker: a visible menu replaces the prompt indicator with its own marker,
# because reedline's `src/engine.rs` does
# `lines.prompt_indicator = menu.indicator()`. The prompt's line break lives in
# PROMPT_INDICATOR_VI_* because starship's init owns PROMPT_COMMAND, so a marker
# carrying no break collapses the input line onto the starship line the moment a
# menu opens. Give every marker the same break.
#
# The style: $abc_menu_style mirrors fish_pager_color_*.
$env.config.menus = ($env.config.menus | each {|m|
    let m = (if ($m.marker | str starts-with "\r\n") { $m } else { $m | update marker $"\r\n($m.marker)" })
    $m | update style ($m.style | merge $abc_menu_style)
})

# Flag and argument completions for external commands. Nushell ships none: only
# internal commands and `extern` declarations carry flags, so without a completer
# `git push -<tab>` opens an empty menu. carapace knows ~1000 CLIs.
#
# Installed only when carapace is on PATH. `null` out of the closure makes
# nushell decline the custom result and run its own file completion instead
# (nu-cli/src/completions/custom_completions.rs:273), which is what should happen
# for a command carapace does not know.
if (which carapace | is-not-empty) {
    # carapace reads these to tell shell builtins apart from real binaries.
    # Resolved once here rather than per keypress, which is what carapace's own
    # generated script does.
    $env.CARAPACE_SHELL_BUILTINS = (help commands | where category != "" | get name | each { split row " " | first } | uniq | str join "\n")
    $env.CARAPACE_SHELL_FUNCTIONS = (help commands | where category == "" | get name | each { split row " " | first } | uniq | str join "\n")

    # ~/.local/share/mise/shims/carapace is a symlink to the mise binary, which
    # re-enters mise on every call: 316ms versus 16ms for the installed binary.
    # At one invocation per keypress that is the difference between instant and
    # sluggish, so resolve past the shim once here. `mise which` costs 13ms and
    # answers with a `latest` symlink that survives patch upgrades.
    let mise_resolved = (do --ignore-errors { ^mise which carapace | str trim } | default "")
    let carapace_bin = if ($mise_resolved | is-not-empty) { $mise_resolved } else { (which carapace).0.path }

    $env.config.completions.external.completer = {|spans|
        # An alias has to be resolved to its target first, or carapace looks up a
        # command that does not exist.
        let expansion = (scope aliases | where name == $spans.0 | get --optional 0.expansion)
        let spans = if ($expansion | is-not-empty) {
            $spans | skip 1 | prepend ($expansion | split row " " | first)
        } else {
            $spans
        }

        # carapace styles every candidate itself, in palette-index ANSI: "blue"
        # for flags, blue+bold for directories. Those ignore the theme, and
        # `selected_text: {attr: r}` reverses them into a solid blue bar. fish
        # paints every candidate alike (fish_pager_color_completion normal), so
        # drop the styles and let $abc_menu_style.text apply.
        let out = (do --ignore-errors { ^$carapace_bin $spans.0 nushell ...$spans } | default "")
        if ($out | is-empty) { null } else { $out | from json | reject --optional style }
    }
}

# Ported from ~/.config/fish/functions. Order matters: `source` is a parse-time
# include, so a file may only call commands defined in an earlier one.
source ./lib/platform.nu
source ./lib/files.nu
source ./lib/completions/claude.nu
source ./lib/aliases.nu
source ./lib/media.nu
source ./lib/dev.nu
source ./lib/maint.nu
source ./lib/chezmoi.nu

# Generated completions need no `source`. Nushell autoloads every .nu file under
# $nu.user-autoload-dirs and $nu.vendor-autoload-dirs after this file runs, and
# skips a missing directory without complaining, so a machine chezmoi has not
# reached yet still gets a working shell. See env.nu for where they land.
#
# lib/completions/ is the exception, sourced above, one file per command:
# autoload runs after this file, and an alias binds to whatever declaration
# exists when the alias itself is parsed. Autoloading claude.nu would leave
# `cr` and `ca` with no completions.
