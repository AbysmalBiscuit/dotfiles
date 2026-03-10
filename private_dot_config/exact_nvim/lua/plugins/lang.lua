-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---@type LazyPluginSpec[]
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      enabled = false,
      completions = { lsp = { enabled = true } },
    },
  },
  {
    "tpope/vim-dadbod",
    lazy = true,
  },

  { "vim-dadbod-ui", lazy = true },
  { "vim-dadbod-completion", lazy = true },
  -- {
  --   "ngynkvn/gotmpl.nvim",
  --   opts = {},
  -- },
}
