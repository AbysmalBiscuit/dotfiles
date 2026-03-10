vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2

vim.keymap.set({ "n", "i" }, "<F4>", function()
  vim.cmd("VimtexView")
end, { desc = "Open PDF at cursor location", buffer = 0 })

local autocmd = vim.api.nvim_create_autocmd

if vim.g.vimtex_quickfix_enabled == 1 then
  autocmd("User", {
    pattern = { "VimtexEventCompileFailed", "VimtexEventCompileSuccess" },
    callback = function()
      vim.cmd("cclose")
      require("trouble").open("quickfix")
    end,
  })
end

-- local mini_pairs_group = vim.api.nvim_create_augroup("custom_mini_pairs_tex", { clear = true })
--
-- autocmd({ "BufEnter", "BufWinEnter" }, {
--   pattern = { "*.tex" },
--   group = mini_pairs_group,
--   once = true,
--   callback = function(_)
--     local MiniPairs = require("mini.pairs")
--     local no_cr_yes_bs = { cr = false, bs = true }
--     for key, value in pairs({
--       ["`"] = { action = "closeopen", pair = "`'", neigh_pattern = "[^%a\\].", register = no_cr_yes_bs },
--       ["``"] = { action = "closeopen", pair = "``''", neigh_pattern = "[^%a\\].", register = no_cr_yes_bs },
--       ["{"] = { action = "closeopen", pair = "{}", neigh_pattern = "[^\\]." },
--       ["\\{"] = { action = "open", pair = "\\{\\}" }, --, neigh_pattern = "[^\\]." },
--       -- ["<"] = { action = "open", pair = "<>", neigh_pattern = ":.", register = no_cr_yes_bs },
--       -- [">"] = { action = "close", pair = "<>", neigh_pattern = "[^\\-].", register = no_cr_yes_bs },
--     }) do
--       MiniPairs.map_buf(0, "i", key, value)
--     end
--   end,
--
--   desc = "Set mini.pairs rules for tex",
-- })

-- local group = vim.api.nvim_create_augroup("custom_tex_group", { clear = true })
-- vim.api.nvim_create_autocmd("BufEnter", {
--   group = group,
--   callback = function()
--     vim.opt_local.wrap = true
--   end,
-- })

-- vim.opt_local.textwidth = 0
vim.opt_local.formatoptions:remove("t")

-- disable virtcolumn in latex files
-- vim.cmd("VirtColumnDisable")

-- enable soft wrap
vim.opt_local.linebreak = true
vim.opt_local.wrap = true
vim.opt_local.conceallevel = 0
vim.opt_local.breakindent = true

-- Configuration for files bigger than a certain size
-- disable for files bigger than 25KB
local max_size = 50 * 1024
local file_size = vim.fn.getfsize(vim.api.nvim_buf_get_name(0))

if file_size > max_size then
  -- Disable expensive or unnecessary features for large files
  Snacks.notify.info("Large LaTeX file, disabling features.")
  vim.b.large_file = true
  vim.opt.cursorline = false
  vim.opt.cursorcolumn = false
  -- vim.opt_local.spell = false
  vim.opt.foldmethod = "manual"
  -- vim.opt_local.syntax = "off"
  -- vim.cmd("TSBufDisable highlight")
  -- optionally disable LSP
  -- vim.cmd("lsp stop")

  -- Disable line numbers
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false

  -- Disable inlay hints
  vim.lsp.inlay_hint.enable(false, { bufnr = 0 })

  -- Disable Treesitter
  vim.treesitter["stop"]()

  -- Disable indent guide
  Snacks.indent.disable()

  -- Disable conceal level
  vim.o.conceallevel = 0

  -- Disable animations
  vim.g.snacks_animate = false

  -- Disable dimming
  Snacks.dim.disable()
end
