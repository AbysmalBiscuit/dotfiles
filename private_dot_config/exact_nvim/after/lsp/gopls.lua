-- local all_filetypes = vim.fn.getcompletion("", "filetype")
-- local all_filetypes = { "bash", "sh", "fish", "toml", "conf", "ini" }
-- local filetypes = { "go", "gomod", "gowork", "gotmpl" }
-- for i = 1, #all_filetypes do
--   table.insert(filetypes, all_filetypes[i] .. ".chezmoitmpl")
-- end

---@type vim.lsp.Config
return {
  -- filetypes = filetypes,
  settings = {
    gopls = {
      templateExtensions = { "tmpl" },
    },
  },
}
