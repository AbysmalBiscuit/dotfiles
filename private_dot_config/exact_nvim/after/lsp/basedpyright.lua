---@type vim.lsp.Config
return {
  settings = {
    basedpyright = {
      disableLanguageServices = true,
      disableOrganizeImports = true,
      analysis = {
        autoSearchPaths = true,
        inlayHints = {
          typeCheckingMode = "strict",
          variableTypes = true,
          callArgumentNames = true,
          functionReturnTypes = true,
          genericTypes = true,
          useTypingExtensions = true,
        },
        -- inlayHints = {
        --   typeCheckingMode = "off",
        --   variableTypes = false,
        --   callArgumentNames = false,
        --   functionReturnTypes = false,
        --   genericTypes = false,
        --   useTypingExtensions = false,
        -- },
      },
    },
  },
}
