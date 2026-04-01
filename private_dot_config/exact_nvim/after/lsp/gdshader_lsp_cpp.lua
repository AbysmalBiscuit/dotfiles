local exe
if vim.g.is_linux then
  exe = "gdshader_lsp_release_linux"
elseif vim.g.is_windows then
  exe = "gdshader_lsp_release_windows.exe"
elseif vim.g.is_macos then
  exe = "gdshader_lsp_release_macos_arm64"
end

---@type vim.lsp.Config
return {
  name = "gdshader-lsp-cpp",
  filetypes = { "gdshader", "gdshaderinc" },
  cmd = { exe, "--stdio" },
  root_markers = { "project.godot" },
  capabilities = vim.lsp.protocol.make_client_capabilities(),
}
