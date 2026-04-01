local gdshader_lsp_cpp_exe = ""
if vim.g.is_linux then
  gdshader_lsp_cpp_exe = "gdshader_lsp_release_linux"
elseif vim.g.is_windows then
  gdshader_lsp_cpp_exe = "gdshader_lsp_release_windows.exe"
elseif vim.g.is_macos then
  gdshader_lsp_cpp_exe = "gdshader_lsp_release_macos_arm64"
end

---@type vim.lsp.Config
return {
  cmd = { "gdshader-lsp", "--stdio" },
  filetypes = { "gdshader", "gdshaderinc" },
  root_markers = { "project.godot" },

  capabilities = vim.lsp.protocol.make_client_capabilities(),

  on_attach = function(client, bufnr)
    if gdshader_lsp_cpp_exe ~= "" and vim.fn.executable(gdshader_lsp_cpp_exe) == 1 then
      client.server_capabilities.completionProvider = nil
    end
  end,
}
