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

    history: {
        max_size: 100_000
        sync_on_enter: true
        file_format: "plaintext"
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
        # the hint completion the way its emacs map does.
        {
            name: accept_hint
            modifier: control
            keycode: char_f
            mode: [emacs vi_normal vi_insert]
            event: { send: historyhintcomplete }
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

# Ported from ~/.config/fish/functions. Order matters: `source` is a parse-time
# include, so a file may only call commands defined in an earlier one.
source ./lib/platform.nu
source ./lib/files.nu
source ./lib/aliases.nu
source ./lib/media.nu
source ./lib/dev.nu
source ./lib/maint.nu

# No `source` for completions. Nushell autoloads every .nu file under
# $nu.user-autoload-dirs and $nu.vendor-autoload-dirs after this file runs, and
# skips a missing directory without complaining, so a machine chezmoi has not
# reached yet still gets a working shell. See env.nu for where they land.
