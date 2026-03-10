---@meta
---Credits for a bunch of the code: https://github.com/catppuccin/nvim

---@alias ColorCode string A string matching the pattern "^#%x%x%x%x%x%x$" (e.g., "#ffffff")

---A table mapping color names to color codes
---@class ColorsTable: table<string, ColorCode>

---@alias HighlightStyles "bold" | "underline" | "undercurl" | "underdouble" | "underdotted" | "underdashed" | "strikethrough" | "reverse" | "inverse" | "italic" | "standout" | "altfont" | "nocombine" | "nobold" | "noitalic" | "nounderline" | "noundercurl" | "nounderdouble" | "nounderdotted" | "nounderdashed" | "nostrikethrough" | "NONE"

---@class HighlightOptions
---@field fg ColorCode?             Foreground color (e.g., "#ff0000" or "Red")
---@field bg ColorCode?             Background color (e.g., "#000000" or "Blue")
---@field sp ColorCode?             Special color (e.g., for underlines, "#ffffff")
---@field blend integer?            Blend with background text color (value between 0 and 100)
---@field bold boolean?             Enable bold text
---@field italic boolean?           Enable italic text
---@field underline boolean?        Enable underline
---@field undercurl boolean?        Enable undercurl
---@field underdouble boolean?      Enable undercurl
---@field underdotted boolean?      Enable undercurl
---@field underdashed boolean?      Enable undercurl
---@field strikethrough boolean?    Enable strikethrough
---@field reverse boolean?          Reverse foreground and background colors
---@field inverse boolean?          Reverse foreground and background colors
---@field standout boolean?         Reverse foreground and background colors
---@field altfont boolean?          Reverse foreground and background colors
---@field nocombine boolean?        Disable combination of styles
---@field link "NONE" | string?     Link to another highlight group
---@field style HighlightStyles[]?  List of styles to be converted (e.g., {"bold", "italic"})
---@field default boolean?          Don't override existing definition |:hi-default|
---@field ctermfg integer?          Sets foreground of cterm color |ctermfg|
---@field ctermbg integer?          Sets background of cterm color |ctermbg|
---@field cterm nil?                cterm attribute map, like |highlight-args|. If not set, cterm attributes will match those from the attribute map documented above.
---@field force boolean?            If true force update the highlight group when it exists.

---@class Terminal
---@field terminal_color_0 ColorCode Black
---@field terminal_color_8 ColorCode Bright black
---@field terminal_color_1 ColorCode Red
---@field terminal_color_9 ColorCode Bright red
---@field terminal_color_2 ColorCode Green
---@field terminal_color_10 ColorCode Bright green
---@field terminal_color_3 ColorCode Yellow
---@field terminal_color_11 ColorCode Bright yellow
---@field terminal_color_4 ColorCode Blue
---@field terminal_color_12 ColorCode Bright blue
---@field terminal_color_5 ColorCode Purple
---@field terminal_color_13 ColorCode Bright purple
---@field terminal_color_6 ColorCode Cyan
---@field terminal_color_14 ColorCode Bright cyan
---@field terminal_color_7 ColorCode White
---@field terminal_color_15 ColorCode Bright white

---@alias HighlightGroupTable table<string, HighlightOptions> Table grouping highlight groups
---@alias NestedHighlightGroupTable table<string,HighlightGroupTable> Nested table grouping highlight groups. It's like a HighlightGroupTable, but with sub-groups

---@class Integrations: { [string]: HighlightGroupTable } Integrations with plugins
---@field lsp HighlightGroupTable LSP semantic token highlights
---@field treesitter NestedHighlightGroupTable Treesitter highlights, this table is nested due to having many categories
---@field treesitter_languages NestedHighlightGroupTable Treesitter highlights per language, this table is nested due to having many categories
---@field blink HighlightGroupTable blink.cmp integration
---@field rainbow_delimiters HighlightGroupTable rainbow_delimiters integration
---@field treesitter_context HighlightGroupTable treesitter_context integration
---@field toggleterm HighlightGroupTable toggleterm integration
---@field neotest HighlightGroupTable neotest integration
---@field noice HighlightGroupTable noice integration
---@field ["virt-column"] HighlightGroupTable "virt-column" integration
---@field snacks HighlightGroupTable Snacks.nvim integration
---@field vimtex HighlightGroupTable vimtex integration

---@class Theme
---Table describing a color theme that will be compiled.
---@field editor HighlightGroupTable? Editor highlight options
---@field syntax HighlightGroupTable? Syntax highlight options
---@field terminal Terminal? Terminal colors
---@field custom HighlightGroupTable? Custom additional overrides
---@field integrations Integrations Integration highlight options

---@class CompileConfig
---@field theme Theme
---@field background "dark" | "light"
---@field flavor string?
---@field compile_path string?
---@field term_colors boolean?
---@field no_italic boolean?
---@field no_bold boolean?
---@field no_underline boolean?
---@field merge boolean?
---@field exclude string[] | table<string, any>?
---@field debug boolean Compiled file will be a .lua file instead of a binary blob

---@class ColorsConfig
---@field compile_opts CompileConfig
