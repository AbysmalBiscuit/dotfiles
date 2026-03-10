---@type LazyPluginSpec[]
return {
  { "akinsho/bufferline.nvim", enabled = false },
  {
    "nvim-mini/mini.pairs",
    enabled = false,
    -- opts = {
    --   -- modes = { command = false },
    --   -- mappings = {
    --   --   -- add don't instert matching ' when preceded by an & for rust
    --   --   ["'"] = { action = "closeopen", pair = "''", neigh_pattern = "[^%a\\&\\<].", register = { cr = false } },
    --   --   ["<"] = { action = "open", pair = "<>", neigh_pattern = "[^\\]." },
    --   --   [">"] = { action = "close", pair = "<>", neigh_pattern = "[^\\]." },
    --   -- },
    -- },
    -- config = function(_, opts)
    --   local map_bs = function(lhs, rhs)
    --     vim.keymap.set("i", lhs, rhs, { expr = true, replace_keycodes = false })
    --   end
    --
    --   map_bs("<C-h>", "v:lua.MiniPairs.bs()")
    --   map_bs("<C-w>", 'v:lua.MiniPairs.bs("\23")')
    --   map_bs("<C-u>", 'v:lua.MiniPairs.bs("\21")')
    --
    --   LazyVim.mini.pairs(opts)
    -- end,
  },
}
