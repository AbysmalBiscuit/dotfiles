local exe = vim.g.is_windows and "taplo.exe" or "taplo"

---@type vim.lsp.Config
return {
  cmd = { vim.fs.normalize("~/.cargo/bin/" .. exe), "lsp", "stdio" },
  filetypes = { "toml" },
  root_markers = { ".git", ".taplo.toml", "taplo.toml" },
}
