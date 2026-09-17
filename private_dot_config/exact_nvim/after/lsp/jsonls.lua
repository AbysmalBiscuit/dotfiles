---@type vim.lsp.Config
return {
  settings = {
    json = {
      schemas = {
        {
          fileMatch = { "hooks.json", "!**/.codex/hooks.json" },
          url = "https://json.schemastore.org/claude-code-settings.json",
        },
        {
          fileMatch = { "hooks-codex.json", "**/.codex/hooks.json" },
          url = "file://"
            .. vim.fs.joinpath(vim.env.XDG_CONFIG_HOME or vim.fs.normalize("~/.config"), "schemas", "codex-hooks.json"),
        },
      },
    },
  },
}
