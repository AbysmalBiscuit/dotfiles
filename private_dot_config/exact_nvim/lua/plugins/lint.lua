-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---@type LazyPluginSpec[]
return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", vim.fn.expand("~/.config/markdownlint-cli2/markdownlint-cli2.yaml"), "--" },
        },
      },
    },
  },
}
