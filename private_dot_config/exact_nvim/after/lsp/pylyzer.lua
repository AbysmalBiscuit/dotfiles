---@type vim.lsp.Config
return {
  cmd = { "pylyzer", "--server" },
  filetypes = { "python" },
  settings = {
    {
      python = {
        checkOnType = true,
        diagnostics = true,
        inlayHints = true,
        smartCompletion = true,
      },
    },
  },
}
