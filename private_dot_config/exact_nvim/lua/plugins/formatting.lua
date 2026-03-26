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
        gdscript = function()
          if vim.fn.executable("gdscript-formatter") == 1 then
            return { "gdscript_formatter" }
          end
          return { "gdformat" }
        end,
      },
      formatters = {
        gdformat = {
          command = "gdformat",
          args = { "-" },
          env = {
            PYTHONIOENCODING = "utf-8",
          },
          condition = function(_, _)
            return vim.fn.filereadable(vim.uv.cwd() .. "/project.godot") == 1
          end,
        },
        gdscript_formatter = {
          command = "gdscript-formatter",
          args = { "--safe" },
          stdin = true,
        },
      },
    },
  },
}
