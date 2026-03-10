-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- dir = "~/Git/github/nvim-treesitter",
    ---@type lazyvim.TSConfig
    opts = {
      highlight = {
        enable = true,
        disable = { "csv" },
      },
      ensure_installed = {
        "fish",
        -- "rust",
        -- "starlark",
      },
    },
  },
  {
    "aaronik/treewalker.nvim",
    keys = {
      { "<S-Down>", "<cmd>Treewalker Down<CR>", mode = { "n", "v" }, noremap = true, silent = true },
      { "<S-Up>", "<cmd>Treewalker Up<CR>", mode = { "n", "v" }, noremap = true, silent = true },
      { "<S-Left>", "<cmd>Treewalker Left<CR>", mode = { "n", "v" }, noremap = true, silent = true },
      { "<S-Right>", "<cmd>Treewalker Right<CR>", mode = { "n", "v" }, noremap = true, silent = true },
    },
    opts = {
      highlight = true,
    },
  },
}
