local catppuccin_editor = {
  ColorColumn = {},  -- used for the columns set with 'colorcolumn'
  Conceal = {},      -- placeholder characters substituted for concealed text (see 'conceallevel')
  Cursor = {},       -- character under the cursor
  lCursor = {},      -- the character under the cursor when |language-mapping| is used (see 'guicursor')
  CursorIM = {},     -- like Cursor, but used when in IME mode |CursorIM|
  CursorColumn = {}, -- Screen-column at the cursor, when 'cursorcolumn' is set.
  CursorLine = {},   -- Screen-line at the cursor, when 'cursorline' is set.  Low-priority if forecrust (ctermfg OR guifg) is not set.
  Directory = {},    -- directory names (and other special names in listings)
  EndOfBuffer = {},  -- filler lines (~) after the end of the buffer.  By default, this is highlighted like |hl-NonText|.
  ErrorMsg = {},     -- error messages on the command line
  VertSplit = {},    -- the column separating vertically split windows
  Folded = {},       -- line used for closed folds
  FoldColumn = {},   -- 'foldcolumn'
  SignColumn = {},   -- column where |signs| are displayed
  SignColumnSB = {}, -- column where |signs| are displayed
  Substitute = {},   -- |:substitute| replacement text highlighting
  LineNr = {},       -- Line number for ":number" and ":#" commands, and when 'number' or 'relativenumber' option is set.
  CursorLineNr = {}, -- Like LineNr when 'cursorline' or 'relativenumber' is set for the cursor line. highlights the number in numberline.
  MatchParen = {},   -- The character under the cursor or just before it, if it is a paired bracket, and its match. |pi_paren.txt|
  ModeMsg = {},      -- 'showmode' message (e.g., "-- INSERT -- ")
  -- MsgArea = {}, -- Area for messages and cmdline, don't set this highlight because of https://github.com/neovim/neovim/issues/17832
  MsgSeparator = {}, -- Separator for scrolled messages, `msgsep` flag of 'display'
  MoreMsg = {},      -- |more-prompt|
  NonText = {},      -- '@' at the end of the window, characters from 'showbreak' and other characters that do not really exist in the text (e.g., ">" displayed when a double-wide character doesn't fit at the end of the line). See also |hl-EndOfBuffer|.
  Normal = {},       -- normal text
  NormalNC = {},     -- normal text in non-current windows
  NormalSB = {},     -- normal text in non-current windows
  NormalFloat = {},  -- Normal text in floating windows.
  FloatBorder = {},
  FloatTitle = {},   -- Title of floating windows
  Pmenu = {},        -- Popup menu: normal item.
  PmenuSel = {},     -- Popup menu: selected item.
  PmenuSbar = {},    -- Popup menu: scrollbar.
  PmenuThumb = {},   -- Popup menu: Thumb of the scrollbar.
  Question = {},     -- |hit-enter| prompt and yes/no questions
  QuickFixLine = {}, -- Current |quickfix| item in the quickfix window. Combined with |hl-CursorLine| when the cursor is there.
  Search = {},       -- Last search pattern highlighting (see 'hlsearch').  Also used for similar items that need to stand out.
  IncSearch = {},    -- 'incsearch' highlighting; also used for the text replaced with ":s///c"
  CurSearch = {},    -- 'cursearch' highlighting: highlights the current search you're on differently
  SpecialKey = {},   -- Unprintable characters: text displayed differently from what it really is.  But not 'listchars' textspace. |hl-Whitespace|
  SpellBad = {},     -- Word that is not recognized by the spellchecker. |spell| Combined with the highlighting used otherwise.
  SpellCap = {},     -- Word that should start with a capital. |spell| Combined with the highlighting used otherwise.
  SpellLocal = {},   -- Word that is recognized by the spellchecker as one that is used in another region. |spell| Combined with the highlighting used otherwise.
  SpellRare = {},    -- Word that is recognized by the spellchecker as one that is hardly ever used.  |spell| Combined with the highlighting used otherwise.
  StatusLine = {},   -- status line of current window
  StatusLineNC = {}, -- status lines of not-current windows Note: if this is equal to "StatusLine" Vim will use "^^^" in the status line of the current window.
  TabLine = {},      -- tab pages line, not active tab page label
  TabLineFill = {},  -- tab pages line, where there are no labels
  TabLineSel = {},   -- tab pages line, active tab page label
  TermCursor = {},   -- cursor in a focused terminal
  TermCursorNC = {}, -- cursor in unfocused terminals
  Title = {},        -- titles for output from ":set all", ":autocmd" etc.
  Visual = {},       -- Visual mode selection
  VisualNOS = {},    -- Visual mode selection when vim is "Not Owning the Selection".
  WarningMsg = {},   -- warning messages
  Whitespace = {},   -- "nbsp", "space", "tab" and "trail" in 'listchars'
  WildMenu = {},     -- current match in 'wildmenu' completion
  WinBar = {},
  WinBarNC = {},
  WinSeparator = {},
}


local catppuccin_syntax = {
  Comment = {},        -- just comments
  SpecialComment = {}, -- special things inside a comment
  Constant = {},       -- (preferred) any constant
  String = {},         -- a string constant: "this is a string"
  Character = {},      --  a character constant: 'c', '\n'
  Number = {},         --   a number constant: 234, 0xff
  Float = {},          --    a floating point constant: 2.3e10
  Boolean = {},        --  a boolean constant: TRUE, false
  Identifier = {},     -- (preferred) any variable name
  Function = {},       -- function name (also: methods for classes)
  Statement = {},      -- (preferred) any statement
  Conditional = {},    --  if, then, else, endif, switch, etc.
  Repeat = {},         --   for, do, while, etc.
  Label = {},          --    case, default, etc.
  Operator = {},       -- "sizeof", "+", "*", etc.
  Keyword = {},        --  any other keyword
  Exception = {},      --  try, catch, throw

  PreProc = {},        -- (preferred) generic Preprocessor
  Include = {},        --  preprocessor #include
  Define = {},         -- preprocessor #define
  Macro = {},          -- same as Define
  PreCondit = {},      -- preprocessor #if, #else, #endif, etc.

  StorageClass = {},   -- static, register, volatile, etc.
  Structure = {},      --  struct, union, enum, etc.
  Special = {},        -- (preferred) any special symbol
  Type = {},           -- (preferred) int, long, char, etc.
  Typedef = {},        --  A typedef
  SpecialChar = {},    -- special character in a constant
  Tag = {},            -- you can use CTRL-] on this
  Delimiter = {},      -- character that needs attention
  Debug = {},          -- debugging statements

  Underlined = {},     -- (preferred) text that stands out, HTML links
  Bold = {},
  Italic = {},
  -- ("Ignore", below, may be invisible...)
  -- Ignore = {}, -- (preferred) left blank, hidden  |hl-Ignore|

  Error = {}, -- (preferred) any erroneous construct
  Todo = {},  -- (preferred) anything that needs extra attention; mostly the keywords TODO FIXME and XXX
  qfLineNr = {},
  qfFileName = {},
  htmlH1 = {},
  htmlH2 = {},
  -- mkdHeading = {},
  -- mkdCode = {},
  mkdCodeDelimiter = {},
  mkdCodeStart = {},
  mkdCodeEnd = {},
  -- mkdLink = {},

  -- debugging
  debugPC = {},         -- used for highlighting the current line in terminal-debug
  debugBreakpoint = {}, -- used for breakpoint colors in terminal-debug
  -- illuminate
  illuminatedWord = {},
  illuminatedCurWord = {},
  -- diff
  diffAdded = {},
  diffRemoved = {},
  diffChanged = {},
  diffOldFile = {},
  diffNewFile = {},
  diffFile = {},
  diffLine = {},
  diffIndexLine = {},
  DiffAdd = {},    -- diff mode: Added line |diff.txt|
  DiffChange = {}, -- diff mode: Changed line |diff.txt|
  DiffDelete = {}, -- diff mode: Deleted line |diff.txt|
  DiffText = {},   -- diff mode: Changed text within a changed line |diff.txt|
  -- NeoVim
  healthError = {},
  healthSuccess = {},
  healthWarning = {},
  -- misc

  -- glyphs
  GlyphPalette1 = {},
  GlyphPalette2 = {},
  GlyphPalette3 = {},
  GlyphPalette4 = {},
  GlyphPalette6 = {},
  GlyphPalette7 = {},
  GlyphPalette9 = {},

  -- rainbow
  rainbow1 = {},
  rainbow2 = {},
  rainbow3 = {},
  rainbow4 = {},
  rainbow5 = {},
  rainbow6 = {},

  -- csv
  csvCol0 = {},
  csvCol1 = {},
  csvCol2 = {},
  csvCol3 = {},
  csvCol4 = {},
  csvCol5 = {},
  csvCol6 = {},
  csvCol7 = {},
  csvCol8 = {},
}

return {
  syntax = catppuccin_syntax,
  editor = catppuccin_editor,
}
