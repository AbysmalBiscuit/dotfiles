local U = require("colors.utils.colors")

-- h(0, "MiniStatuslineModeVisual", { fg = "#1e1e2e", bold = true, bg = "#cba6f7" })
-- h(0, "MiniStatuslineModeReplace", { fg = "#1e1e2e", bold = true, bg = "#f38ba8" })
-- h(0, "MiniStatuslineModeOther", { fg = "#1e1e2e", bold = true, bg = "#94e2d5" })
-- h(0, "MiniStatuslineModeNormal", { fg = "#181825", bold = true, bg = "#89b4fa" })
-- h(0, "MiniStatuslineModeInsert", { fg = "#1e1e2e", bold = true, bg = "#a6e3a1" })
-- h(0, "MiniStatuslineModeCommand", { fg = "#1e1e2e", bold = true, bg = "#fab387" })
-- h(0, "MiniStatuslineInactive", { fg = "#89b4fa", bg = "#181825" })
-- h(0, "MiniStatuslineFilename", { fg = "#cdd6f4", bg = "#181825" })
-- h(0, "MiniStatuslineFileinfo", { fg = "#bac2de", bg = "#45475a" })
-- h(0, "MiniStatuslineDevinfo", { fg = "#bac2de", bg = "#45475a" })

---@type ColorsTable
---Color palette
local C = {
  none = "NONE",

  beige = "#efdcbc",
  beige2 = "#bfb096",
  beige3 = "#b4aa99",
  black = "#18181b",
  black2 = "#0c0c0c",
  black_bright = "#555753",
  pureblack = "#000000",
  purewhite = "#ffffff",
  blue = "#558eff",
  blue2 = "#91CCFF",
  blue3 = "#7db8f5",
  blue4 = "#375780",
  blue5 = "#273E5C",
  blue6 = "#1B2B40",
  blue7 = "#2a4363",
  blue8 = "#569CD6",
  blue_background = "#141F2E",
  -- blue_background = "#0F1824",
  -- alternate_background = "#0D141F",
  alternate_background = "#0D141F",
  cyan = "#06989A",
  cyan2 = "#34E2E2",
  gold = "#FFD700",
  gray = "#333333",
  gray0 = "#6a6a6e",
  gray1 = "#99999d",
  gray2 = "#cbcbcf",
  gray3 = "#b4aa99",
  gray4 = "#262628",
  gray5 = "#7f7f7f",
  gray6 = "#808080",
  gray7 = "#cccccc",
  gray8 = "#282828",
  green = "#11cf45",
  green2 = "#80FFBB",
  green3 = "#93b3a3",
  green4 = "#b1c37c",
  green5 = "#4AA532",
  green6 = "#2BE85F",
  lavender2 = "#c48aff",
  lavender3 = "#725ab9",
  orange = "#ff9d00",
  orange2 = "#FC7A00",
  peach_dark = "#ffa07a",
  -- peach2 = "#fab387",
  peach3 = "#FFAF87",
  pale_red = "#ffc1c1",
  purple = "#75507B",
  purple2 = "#AD7FA8",
  -- red = "#ac4142",
  red2 = "#f0616d",
  red3 = "#CC0000",
  red4 = "#EF2929",
  red5 = "#f38ba8",
  silk = "#ffcfaf",
  magenta = "#ca30ca",
  magenta2 = "#f49ac2",
  magenta3 = "#ca80ca",
  magenta4 = "#dd70dd",
  white = "#e5e5e5",
  white2 = "#dcdccc",
  white3 = "#D3D7CF",
  -- yellow = "#ffd787",
  yellow2 = "#ffe636",
  yellow3 = "#C4A000",
  yellow4 = "#FCE94F",
  yellow5 = "#FFFAB1",

  -- styles
  string_escape = "#83A6C1",

  -- search colors
  search_blue_dark = "#308CC6",
  search_brown = "#7e3100",

  -- Rainbow Colors
  rainbow_red = "#D65A56",
  rainbow_yellow = "#ffe636",
  rainbow_blue = "#569CD6",
  rainbow_orange = "#D68F56",
  rainbow_green = "#78D656",
  rainbow_violet = "#D375D2",
  rainbow_cyan = "#56C5D6",

  -- catppuccin palette
  rosewater = "#f5e0dc",
  flamingo = "#f2cdcd",
  pink = "#f5c2e7",
  mauve = "#cba6f7",
  red = "#f38ba8",
  maroon = "#eba0ac",
  peach = "#fab387",
  yellow = "#f9e2af",
  green_mocha = "#a6e3a1",
  teal = "#94e2d5",
  sky = "#89dceb",
  sapphire = "#74c7ec",
  blue_mocha = "#89b4fa",
  lavender = "#b4befe",
  text = "#cdd6f4",
  subtext1 = "#bac2de",
  subtext0 = "#a6adc8",
  overlay2 = "#9399b2",
  overlay1 = "#7f849c",
  overlay0 = "#6c7086",
  surface2 = "#585b70",
  surface1 = "#45475a",
  surface0 = "#313244",
  base = "#1e1e2e",
  mantle = "#181825",
  crust = "#11111b",
}

---@type ColorsTable
---taken from catppuccin for easier merging
local CP = {
  rosewater = "#f5e0dc",
  flamingo = "#f2cdcd",
  pink = "#f5c2e7",
  mauve = "#cba6f7",
  red = "#f38ba8",
  maroon = "#eba0ac",
  peach = "#fab387",
  yellow = "#f9e2af",
  green = "#a6e3a1",
  teal = "#94e2d5",
  sky = "#89dceb",
  sapphire = "#74c7ec",
  blue = "#89b4fa",
  lavender = "#b4befe",
  text = "#cdd6f4",
  subtext1 = "#bac2de",
  subtext0 = "#a6adc8",
  overlay2 = "#9399b2",
  overlay1 = "#7f849c",
  overlay0 = "#6c7086",
  surface2 = "#585b70",
  surface1 = "#45475a",
  surface0 = "#313244",
  base = "#1e1e2e",
  mantle = "#181825",
  crust = "#11111b",
}

---ABC Color Theme
---@type Theme
local M = {}

M.editor = {
  -- Standard highlight groups

  ---Normal text in non-current windows.
  NormalNC = { bg = C.alternate_background },

  -- CursorLine
  ---Screen-line at the cursor, when 'cursorline' is set. Low-priority if foreground (ctermfg OR guifg) is not set.
  CursorLine = { bg = C.blue6 },
  ---Like LineNr when 'cursorline' is set and 'cursorlineopt' contains "number" or is "both", for the cursor line.
  CursorLineNr = { fg = C.gray7, bg = C.gray8, style = { "bold" } },

  -- Diagnostic
  DiagnosticError = { fg = C.red2 },
  DiagnosticHint = { fg = C.green },
  DiagnosticInfo = { fg = C.blue },
  DiagnosticWarn = { fg = C.orange },

  DiagnosticFloatingError = { fg = C.red2 },
  DiagnosticFloatingHint = { fg = C.green },
  DiagnosticFloatingInfo = { fg = C.blue },
  DiagnosticFloatingWarn = { fg = C.orange },

  DiagnosticSignError = { fg = C.red2, bg = C.gray8 },
  DiagnosticSignHint = { fg = C.green, bg = C.gray8 },
  DiagnosticSignInfo = { fg = C.blue, bg = C.gray8 },
  DiagnosticSignWarn = { fg = C.orange, bg = C.gray8 },
  -- DiagnosticUnderlineWarn = {},

  -- Diffs
  -- Added = { fg = CP.green },
  -- Changed = { fg = CP.blue },
  -- diffAdded = { fg = CP.green },
  -- diffRemoved = { fg = CP.red },
  -- diffChanged = { fg = CP.blue },
  -- diffOldFile = { fg = CP.yellow },
  -- diffNewFile = { fg = CP.peach },
  -- diffFile = { fg = CP.blue },
  -- diffLine = { fg = CP.overlay0 },
  -- diffIndexLine = { fg = CP.teal },

  DiffAdd = { bg = U.darken(CP.green, 0.18, C.blue_background) }, -- diff mode: Added line |diff.txt|
  DiffChange = { bg = U.darken(CP.blue, 0.07, C.blue_background) }, -- diff mode: Changed line |diff.txt|
  DiffDelete = { bg = U.darken(CP.red, 0.18, C.blue_background) }, -- diff mode: Deleted line |diff.txt|
  DiffText = { bg = U.darken(CP.blue, 0.30, C.blue_background) }, -- diff mode: Changed text within a changed line |diff.txt|

  -- DiffAdd = { fg = C.pureblack, bg = C.green },
  -- DiffChange = { fg = C.pureblack, bg = C.orange },
  -- DiffDelete = { fg = C.pureblack, bg = C.red },
  -- DiffText = { fg = C.pureblack, bg = C.red },
  -- Directory = { fg = C.blue, style = { "bold" } },

  -- Folds
  Folded = { fg = C.green3, bg = C.gray },
  FoldedColumn = { fg = C.green3, bg = C.gray8 },
  FoldColumn = { fg = C.green3, bg = C.gray8 },

  -- Search
  -- Last search pattern highlighting (see 'hlsearch').  Also used for similar items that need to stand out.
  Search = { bg = U.darken(C.blue4, 0.6, C.blue_background) },
  -- 'incsearch' highlighting; also used for the text replaced with ":s///c"
  IncSearch = { fg = C.white, bg = U.darken(C.blue4, 0.90, C.blue_background), style = { "bold", "underline" } },
  -- 'cursearch' highlighting: highlights the current search you're on differently
  CurSearch = { fg = C.white, bg = U.brighten(C.blue4, 0.2), style = { "bold", "underline" } },

  -- Search = { fg = C.text, bg = U.darken(C.sky, 0.30, C.base) },
  -- IncSearch = { fg = C.mantle, bg = U.darken(C.sky, 0.90, C.base) },
  -- CurSearch = { fg = C.mantle, bg = C.red },

  -- Gutter
  ColorColumn = { bg = C.blue5 },
  LineNr = { fg = C.gray6, bg = C.gray8 },
  SignColumn = { bg = C.gray8 },

  LspInlayHint = { fg = C.gray5 },
  EndOfBuffer = { fg = C.gray },
  ModeMsg = { fg = C.green, bg = C.gray8 },
  NormalFloat = {},
  Pmenu = { fg = C.white, bg = C.black },
  PmenuSel = { fg = C.pureblack, bg = C.search_blue_dark, style = { "bold" } },
  QuickFixLine = { fg = C.orange2 },

  -- Spellcheck
  SpellBad = { fg = C.blue2, sp = C.red5, style = { "underline" } },
  SpellCap = { fg = C.blue },
  SpellLocal = { fg = C.green2 },

  -- Editor tabs
  TabLine = { fg = C.white, bg = C.black },
  TabLineSel = { fg = C.white, bg = C.search_blue_dark, style = { "bold" } },

  VertSplit = { fg = C.red },
  netrwExe = { fg = C.green2 },

  -- old visual blue style
  -- Visual = { bg = C.blue4 },

  -- new visual catppuccin gray style
  Visual = { bg = U.darken(C.overlay2, 0.3, C.blue_background), bold = true, style = { "bold" } },

  vimCommentTitle = { fg = C.white },
  vimOption = { fg = C.blue },
  vimSep = { fg = C.white },
  WinSeparator = { fg = C.gray0 },

  -- nvim internal colors
  NvimInternalError = { fg = C.red2 },
}

M.syntax = {
  Builtin = { fg = C.magenta4 },
  Boolean = { fg = C.peach, style = { "bold" } },
  Comment = { fg = C.gray5 },
  Conditional = { fg = C.blue, style = { "bold" } },
  Constant = { fg = C.yellow },
  Define = { fg = C.green5, style = { "bold" } },
  Float = { fg = C.orange },
  Function = { fg = C.white },
  Identifier = { fg = C.white },
  Keyword = { fg = C.blue, style = { "bold" } },
  Macro = { fg = C.green5, style = { "bold" } },
  MatchParen = { bg = C.blue7, style = { "bold" } },
  Normal = { fg = C.white, bg = C.blue_background },
  Number = { fg = C.orange },
  -- Operator = { fg = C.white },
  Operator = { fg = C.teal },
  PreProc = { fg = C.orange2 },
  Include = { fg = C.magenta3 },
  Special = { fg = C.blue8, style = { "bold" } },
  Statement = { fg = C.blue },
  String = { fg = C.green },
  Structure = { fg = C.green2 },
  Type = { fg = C.blue2, style = { "bold" } },
  Typedef = { fg = C.blue2, style = { "bold" } },
}

M.integrations = {
  gotmpl = {
    goTmplFunctions = { link = "@function.builtin" },
  },

  lsp = {
    -- ["@lsp"] = {},
    -- ["@lsp.type"] = {},
    -- ["@lsp.mod"] = {},

    -- ["@lsp.mod.builtin"] = { fg = C.magenta4 },
    -- ["@lsp.mod.declaration"] = { style = { "underline" } },
    ["@lsp.mod.declaration"] = {},
    ["@lsp.mod.definition"] = {},

    -- ["@lsp.typemod.class.builtin"] = { fg = C.blue2, style = { "bold" } },
    -- ["@lsp.typemod.class.defaultLibrary"] = { fg = C.blue2, style = { "bold" } },

    -- ["@lsp.typemod.function.declaration"] = { style = { "bold" } },
    -- ["@lsp.typemod.function.defaultLibrary"] = { link = "Builtin" },
    -- ["@lsp.typemod.function.definition"] = { fg = C.white, style = { "bold" } },
    -- ["@lsp.typemod.method.definition"] = { fg = C.white, style = { "bold" } },
    -- ["@lsp.typemod.parameter.definition.python"] = { link = "@parameter" },
    ["@lsp.typemod.class.builtin"] = {},
    ["@lsp.typemod.variable"] = {},
    ["@lsp.typemod.variable.defaultLibrary"] = {},

    -- ["@lsp.type.decorator"] = { fg = C.orange2, bold = false, style = {} },
    -- ["@lsp.type.decorator.rust"] = { link = "Macro" },
    -- ["@lsp.type.enum"] = { style = { "underline" } },
    -- ["@lsp.type.enumMember.zig"] = { link = "@variable.member" },
    -- ["@lsp.type.macro"] = { fg = C.green5, style = { "bold" } },
    -- ["@lsp.type.namespace.zig"] = { fg = C.white },
    -- ["@lsp.type.parameter"] = { link = "@variable.parameter.declaration" },
    -- ["@lsp.type.property"] = {},
    ["@lsp.type.comment"] = {},
    ["@lsp.type.function"] = {},
    ["@lsp.type.decorator"] = {},
    ["@lsp.type.enum"] = {},
    ["@lsp.type.enumMember.zig"] = {},
    ["@lsp.type.macro"] = {},
    ["@lsp.type.method"] = {},
    ["@lsp.type.namespace.zig"] = {},
    ["@lsp.type.parameter"] = {},
    ["@lsp.type.property"] = {},
  },

  lsp_javascript = {
    ["@lsp.type.function.javascript"] = { link = "NONE" },
  },

  lsp_fish = {
    ["@lsp.type.function.fish"] = {},
  },

  lsp_rust = {
    ["@lsp.type.comment.rust"] = { link = "NONE" },
    ["@lsp.type.macro.rust"] = { link = "Macro" },
    -- ["@lsp.mod.documentation.rust"] = {},
    -- ["@lsp.typemod.comment.documentation.rust"] = {},
  },

  ---@type NestedHighlightGroupTable
  treesitter = {
    -- comments
    comment = {
      -- ["@comment.documentation"] = { link = "Comment" },
      -- ["@comment.documentation"] = { fg = C.green },
      ["@comment.documentation.prefix"] = { fg = C.green, bold = true },
    },

    constructor = {
      -- ["@attribute.builtin"] = { fg = colors.orange2, style = { "bold" } },
      ["@constructor"] = { fg = C.magenta4, style = { "bold" } },
    },

    -- constants
    constant = {
      ["@constant.builtin"] = { link = "Boolean" }, -- For identifiers referring to modules and namespaces.
    },

    decorator = {
      ["@decorator"] = { fg = C.orange2, bold = true, nocombine = true },
      -- ["@decorator.identifier"] = { fg = C.orange2, bold = true, nocombine = true },
      -- ["@decorator.name"] = { fg = C.white, bold = false, nocombine = true },
      -- ["@decorator.operator"] = { link = "@decorator"},
    },

    -- functions
    ["function"] = {
      ["@function"] = { fg = C.white },
      ["@function.builtin"] = { fg = C.magenta4, style = { "bold" } },
      ["@function.call"] = { fg = C.white },
      ["@function.macro"] = { fg = C.green5, style = { "bold" } },
    },

    -- keywords
    keyword = {
      ["@keyword"] = { fg = C.blue, style = { "bold" } },
      ["@keyword.conditional"] = { fg = C.blue, style = { "bold" } },
      ["@keyword.function"] = { link = "@keyword" },
      ["@keyword.import"] = { link = "@keyword" },
      ["@keyword.modifier"] = { link = "@keyword" },
      ["@keyword.operator"] = { link = "@keyword" },
      ["@keyword.return"] = { link = "@keyword" },
      ["@keyword.repeat"] = { link = "@keyword" },
      ["@keyword.exception"] = { link = "@keyword" },
    },

    module = {
      ["@module"] = { fg = C.green2, style = { "bold" } },
      ["@module.builtin"] = { fg = C.green2, sp = C.magenta4, style = { "bold" } },
    },

    namespace = {
      ["@namespace"] = { fg = C.green2, style = { "italic" } },
    },

    operator = {
      ["@operator.redirect"] = { fg = C.peach3 },
    },

    parameter = {
      ["@parameter"] = { fg = C.white }, -- Same as TSField.
    },

    property = {
      ["@property"] = { fg = C.white }, -- Same as TSField.
    },

    punctuation = {
      -- punctuation
      ["@punctuation.bracket"] = { fg = C.gold },
      ["@punctuation.bracket.regex"] = { fg = C.gold, bold = true },
      ["@punctuation.delimiter"] = { fg = C.gold },
      -- ["@punctuation.delimiter"] = { fg = colors.white },
    },

    regex = {
      -- ["@regex.named_capturing_group"] = { link = "@punctuation.bracket.regex" },
      ["@regex.group_syntax"] = { fg = C.string_escape, bold = true },
      ["@regex.group_name"] = { bold = true },
    },

    ["string"] = {
      -- strings
      ["@string"] = { fg = C.green },
      ["@string.escape"] = { fg = C.lavender2, style = { "bold" } },
      ["@string.regexp"] = { fg = C.green },
      ["@string.template"] = { fg = C.green },
      ["@string.documentation"] = { fg = C.green },
    },

    ["type"] = {
      -- type
      ["@type.builtin"] = { fg = C.blue2, style = { "bold" } },
    },

    variable = {
      -- variables
      ["@variable"] = { fg = C.white },
      --- Variable names that are defined by the languages.
      ["@variable.builtin"] = { fg = C.magenta4 },
      --- Special variables that refer to a class instance, like `this` in JavaScript or `self` in Python.
      ["@variable.instance_reference"] = { fg = C.orange2, style = { "bold" } },
      ["@variable.class_reference"] = { fg = C.orange2, style = { "bold" } },
      ["@variable.parameter"] = { fg = C.text },
      -- ["@variable.parameter.argument"] = { fg = C.green_mocha },
      ["@variable.parameter.argument"] = {},
      ["@variable.member"] = { fg = C.lavender },
      ["@variable.parameter.declaration"] = { fg = C.text, style = { "bold" } },
    },
  },

  ---@type NestedHighlightGroupTable
  treesitter_languages = {
    --treesitter languages

    bash = {
      ["@function.call.bash"] = { fg = C.teal },
      ["@function.builtin.bash"] = { link = "@function.builtin" },
      ["@variable.parameter.bash"] = { link = "@variable.parameter.argument" },
      -- ["@variable.parameter.argument.bash"] = {},
    },

    cython = {
      -- ["@operator.cython"] = {},
    },

    -- help2man
    -- Treesitter
    --   - @function.call.fish links to @function.call   priority: 100   language: fish
    --
    -- Semantic Tokens
    --   - @lsp.type.function.fish links to @function   priority: 125
    --   - @lsp.mod.global.fish links to @lsp   priority: 126
    --   - @lsp.typemod.function.global.fish links to @lsp   priority: 127
    fish = {
      ["@function.call.fish"] = { fg = C.teal },
      ["@operator.redirect.fish"] = { fg = C.peach3 },
      ["@variable.parameter.fish"] = { fg = C.yellow5 },
    },

    gdscript = {
      ["@attribute.gdscript"] = { link = "@decorator.name" },
    },

    gotmpl = {
      ["@function.gotmpl"] = { link = "goTmplFunctions" },
    },

    json = {
      -- JSON
      ["@property.json"] = { fg = C.green },
      ["@property.jsonc"] = { fg = C.green },
    },

    latex = {
      ["@function.latex"] = { fg = C.blue },
    },

    markdown = {
      -- ["@default.markdown"] = { fg = C.white },
    },

    rust = {
      -- rust
      ["@variable.parameter.declaration.rust"] = { link = "@variable.parameter.declaration" },
      -- ["@comment.documentation.rust"] = { fg = C.green },
    },

    python = {
      -- Python
      ["@decorator.name.python"] = { link = "@decorator.name" },
      ["@magic_method.python"] = { link = "@function.builtin" },
      ["@constructor.python"] = { style = { "bold" } },
      ["@regex.named_capturing_group.python"] = { link = "@punctuation.bracket.regex" },
    },

    zig = {
      -- Zig
      ["@attribute.zig"] = { fg = C.silk, style = { "bold" } },
      ["@boolean.zig"] = { link = "Boolean" },
      ["@comment.zig"] = { fg = C.gray5 },
      ["@constant.zig"] = { fg = C.white },
      ["@function.builtin.zig"] = {},
      ["@keyword.exception.zig"] = { fg = C.yellow, style = { "bold" } },
      ["@keyword.repeat.zig"] = { fg = C.blue },
      ["@number.float.zig"] = { fg = C.blue },
      ["@type.builtin.zig"] = { fg = C.blue2, style = { "bold" } },
      ["@variable.parameter.zig"] = { fg = C.white },
      ["@variable.zig"] = { fg = C.white },
      ["@zigBlock"] = { fg = C.yellow, style = { "bold" } },
    },
  },

  blink_cmp = {
    BlinkCmpMenuBorder = { fg = C.white },
    BlinkCmpDocBorder = { fg = C.white },
    BlinkCmpSignatureHelpBorder = { fg = C.white },
  },

  blink_indent = {
    BlinkIndentYellowUnderline = { sp = C.rainbow_yellow, style = { "underline" } },
    BlinkIndentVioletUnderline = { sp = C.rainbow_violet, style = { "underline" } },
    BlinkIndentBlueUnderline = { sp = C.rainbow_blue, style = { "underline" } },
    BlinkIndentOrangeUnderline = { sp = C.rainbow_orange, style = { "underline" } },
    BlinkIndentRedUnderline = { sp = C.rainbow_red, style = { "underline" } },
    BlinkIndentCyanUnderline = { sp = C.rainbow_cyan, style = { "underline" } },
    BlinkIndentGreenUnderline = { sp = C.rainbow_green, style = { "underline" } },
  },

  blink_pairs = {
    BlinkPairsUnmatched = { ctermfg = 7, ctermbg = 9, fg = C.white, bg = C.red2, style = { "bold" } },
    BlinkPairsMatchParen = { link = "MatchParen" },
  },

  rainbow_delimiters = {
    -- Rainbow Delimiters
    RainbowDelimiterYellow = { fg = C.rainbow_yellow },
    RainbowDelimiterRed = { fg = C.rainbow_red },
    RainbowDelimiterBlue = { fg = C.rainbow_blue },
    RainbowDelimiterOrange = { fg = C.rainbow_orange },
    RainbowDelimiterGreen = { fg = C.rainbow_green },
    RainbowDelimiterViolet = { fg = C.rainbow_violet },
    RainbowDelimiterCyan = { fg = C.rainbow_cyan },
  },

  treesitter_context = {
    -- Treesitter Context
    TreesitterContextBottom = { sp = C.gray6, style = { "underline" } },
    -- TreesitterContextLineNumberBottom = { sp = colors.gray6, style = { "underline" } }, -- Uncomment if needed
  },

  -- toggleterm = {
  --   ToggleTerm1SignColumn = { bg = C.blue_background },
  --   -- ToggleTerm1NormalFloat ={ links to Normal},
  --   ToggleTerm1StatusLine = { bg = C.blue_background },
  --   ToggleTerm1StatusLineNC = { bg = C.blue_background },
  --   ToggleTerm1EndOfBuffer = { bg = C.blue_background },
  --   -- ToggleTerm1FloatBorder ={ links to Normal},
  --   ToggleTerm1WinBar = { bg = C.blue_background },
  --   ToggleTerm1Normal = { bg = C.blue_background },
  --   ToggleTerm1WinBarNC = { bg = C.blue_background },
  -- },

  neotest = {
    -- Neotest
    NeotestPassed = { fg = C.green, bg = C.gray8 },
  },

  noice = {
    NoiceCmdlineIcon = { fg = CP.sky, bg = C.blue_background },
    NoiceCmdlinePopupBorder = { fg = CP.lavender2, bg = C.blue_background },
  },

  ["virt-column"] = {
    VirtColumn = { fg = C.blue5 },
  },

  snacks = {
    -- SnacksPickerSearch = { link = "IncSearch" },
    SnacksPickerSearch = { link = "IncSearch" },
    SnacksPickerMatch = { link = "IncSearch" },

    -- Snacks notifier
    SnacksNotifierTitleInfo = { fg = CP.blue, style = { "noitalic" } },
    SnacksNotifierTitleWarn = { fg = CP.yellow, style = { "noitalic" } },
    SnacksNotifierTitleDebug = { fg = CP.peach, style = { "noitalic" } },
    SnacksNotifierTitleError = { fg = CP.red, style = { "noitalic" } },
    SnacksNotifierTitleTrace = { fg = CP.rosewater, style = { "noitalic" } },

    -- Snacks dashboard
    SnacksDashboardFooter = { fg = CP.yellow, style = { "noitalic" } },
  },

  vimtex = {
    texOptSep = { link = "NONE" },
    texCmdRefConcealed = { link = "Keyword" },
    texCmd = { link = "Keyword" },
    texRefConcealedArg = { link = "@variable.parameter" },
    texNewcmdArgName = { link = "@variable.parameter" },
    texDefArgName = { link = "@variable.parameter" },
    texArg = { link = "@variable.parameter" },
  },
}

M.terminal = {
  -- terminal_color_0 = C.black2,
  -- terminal_color_8 = C.black_bright,

  -- terminal_color_1 = C.red3,
  -- terminal_color_9 = C.red4,

  terminal_color_2 = C.green,
  terminal_color_10 = C.green6,

  terminal_color_3 = C.yellow3,
  terminal_color_11 = C.yellow4,

  terminal_color_4 = C.blue,
  terminal_color_12 = C.blue2,

  -- terminal_color_5 = C.purple,
  -- terminal_color_13 = C.purple2,

  -- terminal_color_6 = C.cyan,
  -- terminal_color_14 = C.cyan2,

  -- terminal_color_7 = C.white3,
  -- terminal_color_15 = C.white,
}

return M
