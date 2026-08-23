# The "abc" theme, shared with nvim (~/.config/nvim/lua/colors/abc.lua) and fish
# (~/.config/fish/conf.d/fish_frozen_theme.fish).
#
# Where fish has an equivalent colour, fish wins: those are the ones already
# burned into muscle memory at a prompt. Everything nushell has and fish does
# not (tables, cell paths, closures, signatures) comes from the nvim palette.

export const abc = {
    # greys and text
    text: "#cdd6f4"
    white: "#e5e5e5"
    subtext: "#bac2de"
    overlay1: "#7f849c"
    overlay0: "#6c7086"
    gray0: "#6a6a6e"
    gray5: "#7f7f7f"
    surface2: "#585b70"
    background: "#0b111a"

    # accents
    blue: "#558eff"       # fish_color_command / keyword
    blue2: "#91ccff"
    sapphire: "#74c7ec"
    sky: "#89dceb"
    lavender: "#b4befe"
    lavender2: "#c48aff"  # fish_color_escape
    magenta4: "#dd70dd"
    mauve: "#cba6f7"
    rosewater: "#f5e0dc"
    teal: "#94e2d5"       # fish_color_operator / end
    green: "#11cf45"      # fish_color_quote
    green4: "#3dc870"
    green_mocha: "#a6e3a1"
    yellow: "#f9e2af"
    gold: "#ffd700"       # nvim @punctuation.bracket
    amber: "#b3a06d"      # fish_pager_color_description
    orange: "#ffaa00"     # fish_color_number
    peach: "#fab387"
    peach3: "#ffaf87"     # fish_color_redirection / nvim @operator.redirect
    red: "#f05050"        # fish_color_error
    search: "#308cc6"     # fish_color_search_match
    selection: "#3a4456"  # fish_color_selection background
}

# $env.config.color_config
export const abc_theme = {
    separator: $abc.overlay0
    leading_trailing_space_bg: { attr: n }
    header: { fg: $abc.blue2 attr: b }
    empty: $abc.overlay0

    # value colours in table output
    bool: { fg: $abc.peach attr: b }
    int: $abc.orange
    float: $abc.orange
    range: $abc.orange
    filesize: $abc.teal
    duration: $abc.teal
    datetime: $abc.mauve
    string: $abc.white
    glob: $abc.sky
    semver: $abc.sapphire
    semver-range: $abc.sapphire
    nothing: $abc.overlay1
    binary: $abc.text
    binary_null_char: $abc.overlay0
    binary_printable: $abc.teal
    binary_whitespace: $abc.green4
    binary_ascii_other: $abc.mauve
    binary_non_ascii: $abc.yellow
    cell-path: $abc.lavender
    record: $abc.text
    list: $abc.text
    block: $abc.text
    closure: $abc.rosewater
    row_index: $abc.gray0

    hints: $abc.overlay0
    search_result: { fg: $abc.background bg: $abc.search }
    selection: { bg: $abc.selection attr: b }
    selection_cursor: { attr: n }

    # ---- shapes: the command-line syntax highlighter ----

    # A resolved command, internal or external, gets fish's command colour. An
    # external that `which` could not find gets fish's error colour, which is
    # what highlight_resolved_externals buys.
    shape_internalcall: { fg: $abc.blue attr: b }
    shape_external_resolved: { fg: $abc.blue attr: b }
    shape_external: $abc.red
    shape_custom: { fg: $abc.rosewater attr: b }
    shape_keyword: { fg: $abc.blue attr: b }

    shape_operator: { fg: $abc.teal attr: b }
    shape_pipe: { fg: $abc.teal attr: b }
    shape_redirection: $abc.peach3
    shape_flag: $abc.text

    shape_string: $abc.green
    shape_raw_string: $abc.green
    shape_string_interpolation: { fg: $abc.lavender2 attr: b }
    shape_glob_interpolation: { fg: $abc.lavender2 attr: b }
    shape_globpattern: $abc.sky

    shape_int: $abc.orange
    shape_float: $abc.orange
    shape_range: $abc.orange
    shape_bool: { fg: $abc.peach attr: b }
    shape_nothing: $abc.overlay1
    shape_datetime: $abc.mauve
    shape_binary: $abc.mauve

    shape_filepath: $abc.sky
    shape_directory: $abc.sky
    shape_externalarg: $abc.white
    shape_literal: $abc.white

    shape_variable: $abc.magenta4
    shape_vardecl: { fg: $abc.text attr: b }
    shape_signature: $abc.sapphire
    shape_match_pattern: $abc.green_mocha

    # Collection literals are coloured on their brackets only, so they follow
    # nvim's @punctuation.bracket rather than getting a colour each.
    shape_list: $abc.gold
    shape_record: $abc.gold
    shape_table: $abc.gold
    shape_block: $abc.gold
    shape_closure: $abc.gold
    shape_matching_brackets: { bg: $abc.surface2 attr: b }

    shape_garbage: { fg: $abc.red attr: b }
}

# Applied to every entry in $env.config.menus. Mirrors fish_pager_color_*.
export const abc_menu_style = {
    text: $abc.text
    selected_text: { attr: r }
    description_text: $abc.amber
    match_text: { fg: "#ffffff" attr: bu }
    selected_match_text: { fg: "#ffffff" attr: bur }
}
