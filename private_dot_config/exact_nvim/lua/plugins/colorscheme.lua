-- Set the colorscheme
local filepath = vim.fn.expand("~/.config/nvim/colors/abc.lua")
if not vim.fn.filereadable(filepath) or vim.env.RECOMPILE_COLORSCHEME ~= nil then
  vim.notify("recompiling colorscheme")
  local colors = require("colors")
  ---@type Theme
  local abc_theme = require("colors.abc")

  -- colors.compile({
  --   flavor = "abc",
  --   theme = abc_theme,
  --
  --   -- compile_path = vim.fn.stdpath("cache") .. "/my_compiled_themes",
  --   compile_path = vim.fn.expand("~/.config/nvim/colors"),
  --   term_colors = true,
  --   no_italic = false,
  --   no_bold = false,
  --   no_underline = false,
  -- })

  -- utils.printtbl(tbl)

  colors.setup({
    compile_opts = {
      flavor = "abc",
      theme = abc_theme,
      -- compile_path = vim.fn.stdpath("cache") .. "/my_compiled_themes",
      -- compile_path = vim.fn.expand("~/.config/nvim/colors/abc"),
      term_colors = true,
      no_italic = false,
      no_bold = false,
      no_underline = false,
      merge = true,
      exclude = {
        "@parameter",
        -- "@variable",
      },
      debug = true,
    },
  })

  colors.compile()
end

---@type LazyPluginSpec[]
return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
  {
    "catppuccin/nvim",
    lazy = true,
    name = "catppuccin",
    opts = {
      styles = { -- Handles the styles of general hi groups (see `:h highlight-args`):
        comments = {}, -- Change the style of comments
        conditionals = {},
        -- loops = {},
        -- functions = {},
        -- keywords = {},
        -- strings = {},
        -- variables = {},
        -- numbers = {},
        -- booleans = {},
        -- properties = {},
        -- types = {},
        -- operators = {},
        -- miscs = {}, -- Uncomment to turn off hard-coded styles
      },
      -- lsp_styles = { -- Handles the style of specific lsp hl groups (see `:h lsp-highlight`).
      --   virtual_text = {
      --     errors = { "italic" },
      --     hints = { "italic" },
      --     warnings = { "italic" },
      --     information = { "italic" },
      --     ok = { "italic" },
      --   },
      -- },
    },
  },
}
