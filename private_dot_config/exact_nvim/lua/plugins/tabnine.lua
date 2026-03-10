-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

-- Variable to track if tabnine is enabled or disabled
vim.g.tabnine_enabled = false

if true then
  return {}
end

-- Get platform dependant build script
local function tabnine_build_path()
  -- Replace vim.uv with vim.loop if using NVIM 0.9.0 or below
  if vim.uv.os_uname().sysname == "Windows_NT" then
    return "pwsh.exe -file .\\dl_binaries.ps1"
  else
    return "./dl_binaries.sh"
  end
end

local function tabnine_log_path()
  if vim.uv.os_uname().sysname == "Windows_NT" then
    return vim.fn.expand("~/AppData/Local/nvim/state/tabnine.log")
  else
    return vim.fn.expand("~/.local/state/nvim/tabnine.log")
  end
end

---@type LazyPluginSpec[]
return {
  {
    "codota/tabnine-nvim",
    build = tabnine_build_path(),

    cmd = {
      "TabnineStatus",
      "TabnineDisable",
      "TabnineEnable",
      "TabnineToggle",
      "TabnineChat",
      "TabnineLoginWithAuthToken",
      "TabnineFix",
      "TabnineTest",
      "TabnineExplain",
      "TabnineAccept",
      "TabnineReject",
    },
    -- keys = {
    --   { "<C-f>", mode = { "i" }, desc = "Accept tabnine suggestion" },
    -- },
    config = function()
      require("tabnine.status").status()

      require("tabnine").setup({
        disable_auto_comment = false,
        accept_keymap = false,
        dismiss_keymap = false,
        debounce_ms = 800,
        suggestion_color = { gui = "#7f7f7f", cterm = 127 },
        exclude_filetypes = { "TelescopePrompt", "NvimTree" },
        log_file_path = tabnine_log_path(), -- absolute path to Tabnine log file
      })
      -- vim.keymap.set('i', '<C-space>', require("tabnine.completion").complete, { desc = "Trigger tabnine completion" })
      -- vim.keymap.set("n", "<leader>ttnc", require("tabnine.chat").open, { desc = "Open tabnine chat window" })
    end,
  },
}
