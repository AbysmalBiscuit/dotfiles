---@type vim.lsp.Config
return {
  cmd = { "cspell-lsp", "--stdio" },
  filetypes = {
    "lua",
    "python",
    "javascript",
    "typescript",
    "html",
    "css",
    "json",
    "yaml",
    "markdown",
    "gitcommit",
    "tex",
    "latex",
    "sty",
  },
  root_markers = { ".git", "cspell.json", ".cspell.json" },
  settings = {
    cspell = {},
  },
  handlers = {
    -- This handles the "client/registerCapability" which is causing the crash
    ["client/registerCapability"] = function(_, result, ctx)
      -- Just return an empty response so the server doesn't hang or crash the RPC
      return { result = nil, error = nil }
    end,
    -- Also good practice to handle workspace/configuration
    -- ["workspace/configuration"] = function(_, result, ctx)
    --   return { {} }
    -- end,
  },
}
