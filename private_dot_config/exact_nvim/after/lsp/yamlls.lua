---@type vim.lsp.Config
return {
  handlers = {
    -- This handles the "client/registerCapability" which is causing the crash
    ["client/registerCapability"] = function(_, result, ctx)
      -- Just return an empty response so the server doesn't hang or crash the RPC
      return { result = nil, error = nil }
    end,
  },
}
