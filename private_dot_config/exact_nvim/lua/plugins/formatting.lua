-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

local has_gdscript_formatter = vim.fn.executable("gdscript-formatter") == 1
local has_gdformat = vim.fn.executable("gdformat") == 1

---@type LazyPluginSpec[]
return {
  {
    "stevearc/conform.nvim",
    ---@type conform.setupOpts
    opts = {
      formatters_by_ft = {
        latex = { "latexindent" },
        -- python = { "ruff" },
        -- rust = { "rustfmt" },
        -- javascript = { "prettierd", "prettier", stop_after_first = true },
        -- typescript = { "prettierd", "prettier", stop_after_first = true },
        gdscript = { "gdformat_custom", "gdscript-formatter_custom" },
      },
      formatters = {
        -- gdformat = {
        -- command = "gdformat",
        -- args = { "-" },
        -- env = {
        -- PYTHONIOENCODING = "utf-8",
        -- },
        -- condition = function(_, _)
        -- return vim.fn.filereadable(vim.uv.cwd() .. "/project.godot") == 1
        -- end,
        -- },
        -- ["gdscript-formatter"] = {
        -- command = "gdscript-formatter",
        -- args = { "--safe" },
        -- stdin = true,
        -- },
        gdformat_custom = {
          inherit = "gdformat",
          condition = function(ctx)
            return has_gdformat and not has_gdscript_formatter
          end,
        },
        ["gdscript-formatter_custom"] = {
          inherit = "gdscript-formatter",
          condition = function(ctx)
            return has_gdscript_formatter
          end,
          prepend_args = { "--safe" },
        },
        ["gdscript-reorder"] = {
          inherit = "gdscript-formatter",
          prepend_args = { "--reorder-code" },
        },
      },
    },
  },
  {
    "godlygeek/tabular",
    cmd = {
      "Tabularize",
      "AddTabularPattern",
    },
  },
}
