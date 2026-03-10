---@diagnostic disable-next-line: unused-local
local treesitter_ref = {
  ["@field"] = {}, -- For fields.
  ["@property"] = {}, -- Same as TSField.

  ["@include"] = {}, -- For includes: #include in C, use or extern crate in Rust, or require in Lua.
  ["@operator"] = {}, -- For any operator: +, but also -> and * in cp.
  ["@keyword.operator"] = {}, -- For new keyword operator
  ["@punctuation.special"] = {}, -- For special punctuation that does not fall in the categories before.

  ["@float"] = {}, -- For all numbers
  ["@boolean"] = {}, -- For booleans.

  ["@constructor"] = {}, -- For constants
  ["@conditional"] = {}, -- For keywords related to conditionals.
  ["@repeat"] = {}, -- For keywords related to loops.
  ["@exception"] = {}, -- For exception related keywords.

  -- builtin
  ["@constant.builtin"] = {}, -- For identifiers referring to modules and namespaces.
  ["@type"] = {}, -- For types.
  ["@type.builtin"] = {}, -- For builtin types.
  ["@variable.builtin"] = {}, -- Variable names that are defined by the languages, like this or self.

  ["@function"] = {}, -- For function (calls and definitions).
  ["@function.macro"] = {}, -- For macro defined functions (calls and definitions): each macro_rules in Ruscp.
  ["@parameter"] = {}, -- For parameters of a function.
  ["@keyword.function"] = {}, -- For keywords used to define a function.
  ["@keyword"] = {}, -- For keywords that don't fall in previous categories.
  ["@keyword.return"] = {}, -- For constants that are defined by macros: NULL in cp.
  -- TSError = {}, -- For syntax/parser errors.
  -- rustTSField = {}, -- For fields.
  ["@label"] = {}, -- For labels: label: in C and :label: in Lua.
  ["@method"] = {}, -- For method calls and definitions.
  -- TSNone              = {},                        -- For delimiters ie: .
  -- TSPunctBracket = {}, -- For brackets and parenthesis.
  ["@punctuation.bracket"] = {}, -- For brackets and parenthesis.
  ["@string"] = {}, -- For strings.
  ["@string.regex"] = {}, -- For regexes.

  -- TSSymbol            = {},     -- Any variable name that does not have another highlighcp.
  ["@tag.attribute"] = {}, -- Tags like html tag names.
  ["@tag"] = {}, -- Tags like html tag names.
  ["@tag.delimiter"] = {}, -- Tag delimiter like < > /
  ["@text"] = {}, -- For strings considered text in a markup language.

  -- TSEmphasis          = {},  -- urls, links and emails
  ["@text.literal"] = {}, -- used for inline code in markdown and for doc in python (""")
  ["@text.reference"] = {}, -- references
  ["@text.title"] = {}, -- titles like: # Example
  ["@text.emphasis"] = {}, -- bold
  ["@text.strong"] = {}, -- italic
  ["@string.escape"] = {}, -- For escape characters within a string.

  -- toml
  ["@property.toml"] = {}, -- Differentiates between string and properties

  -- json
  ["@label.json"] = {}, -- For labels: label: in C and :label: in Lua.

  -- lua
  ["@constructor.lua"] = {}, -- For constructor calls and definitions: = { } in Lua, and Java constructors.

  -- typescript
  ["@constructor.typescript"] = {},

  -- TSX (Typescript React)
  ["@constructor.tsx"] = {},
  ["@tag.attribute.tsx"] = {},

  -- cpp
  ["@property.cpp"] = {},

  -- yaml
  ["@field.yaml"] = {}, -- For fields.
}
