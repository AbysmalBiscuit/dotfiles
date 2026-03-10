-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---@type LazyPluginSpec[]
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        latex = { "latexindent" },
        -- python = { "ruff" },
        -- rust = { "rustfmt" },
        -- javascript = { "prettierd", "prettier", stop_after_first = true },
        -- typescript = { "prettierd", "prettier", stop_after_first = true },
      },
    },
  },
}
