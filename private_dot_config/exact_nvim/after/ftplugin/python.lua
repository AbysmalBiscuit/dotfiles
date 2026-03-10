vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4

-- local autocmd = vim.api.nvim_create_autocmd
-- local mini_pairs_group = vim.api.nvim_create_augroup("custom_mini_pairs_python", { clear = true })
--
-- autocmd({ "BufEnter", "BufWinEnter" }, {
--   pattern = { "*.py" },
--   group = mini_pairs_group,
--   once = true,
--   callback = function(_)
--     local MiniPairs = require("mini.pairs")
--     local no_cr_yes_bs = { cr = false, bs = true }
--     for key, value in pairs({
--       --special strings
--       ["'"] = {
--         action = "closeopen",
--         pair = "''",
--         neigh_pattern = "[0-9rft%s%c!\"#$%%&'()*+,-./:;<=>?@%[%]^_`{|}~].",
--         register = no_cr_yes_bs,
--       },
--       ['"'] = {
--         action = "closeopen",
--         pair = '""',
--         neigh_pattern = "[0-9rft%s%c!\"#$%%&'()*+,-./:;<=>?@%[%]^_`{|}~].",
--         register = no_cr_yes_bs,
--       },
--     }) do
--       MiniPairs.map_buf(0, "i", key, value)
--     end
--   end,
--   desc = "Set mini.pairs rules for rust",
-- })
