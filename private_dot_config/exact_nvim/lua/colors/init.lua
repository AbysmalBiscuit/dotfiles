local compiler_mod = require("colors.compiler")
local M = {}

---@type ColorsConfig
local default_config = {
  compile_opts = {
    background = "dark",
    flavor = "default",
    compile_path = vim.fn.expand("~/.config/nvim/colors/abc"),
    term_colors = false,
    no_italic = false,
    no_bold = false,
    no_underline = false,
    merge = false,
    exclude = {},
    debug = true,
  },
}

---Common Rainbow delimiters
---@type string[]
M.rainbow_highlight = {
  "RainbowDelimiterYellow",
  "RainbowDelimiterViolet",
  "RainbowDelimiterBlue",
  "RainbowDelimiterOrange",
  "RainbowDelimiterRed",
  "RainbowDelimiterCyan",
  "RainbowDelimiterGreen",
}

local did_setup = false

---@param opts? ColorsConfig
M.setup = function(opts)
  did_setup = true
  opts = opts or {}

  ---@type ColorsConfig
  M.config = vim.tbl_deep_extend("force", default_config, opts)
  M.compile_path = M.config.compile_opts.compile_path
end

M.compile = function()
  compiler_mod.compile(M.config.compile_opts)
end
M.flatten_theme = compiler_mod.flatten_theme

---Load a compiled ABC theme
---@param merge boolean? When true merge the theme on top of the existing one. When false load it as a completely new theme
M.load = function(merge)
  if not did_setup then
    M.setup()
  end
  local f = loadfile(M.compile_path)
  if not f then
    M.compile()
    f = assert(loadfile(M.compiled_path), "could not load cache")
  end
  f(merge or M.config.compile_opts.merge)

  -- Clear compile opts to not store the theme definition in memory
  M.config.compile_opts = nil
end

return M
