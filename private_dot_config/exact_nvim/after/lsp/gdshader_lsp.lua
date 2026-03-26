---@type vim.lsp.Config
return {
  filetypes = { "gdshader" },
  root_markers = { "project.godot" },
  -- filetypes = filetypes,
  on_attach = function(client, bufnr)
    vim.opt_local.expandtab = false
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
    vim.opt_local.softtabstop = 0
  end,
  settings = {},
}
