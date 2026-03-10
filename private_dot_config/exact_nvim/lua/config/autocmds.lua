-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local autocmd = vim.api.nvim_create_autocmd

autocmd({ "LspDetach" }, {
  group = vim.api.nvim_create_augroup("LspStopWithLastClient", {}),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or not client.attached_buffers then
      return
    end
    for buf_id in pairs(client.attached_buffers) do
      if buf_id ~= args.buf then
        return
      end
    end
    client:stop()
  end,
  desc = "Stop lsp client when no buffer is attached",
})

-- Fix conceallevel for json files
autocmd({ "FileType" }, {
  group = vim.api.nvim_create_augroup("markdown_conceal", { clear = true }),
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

--------------------------------------------------------------------------------
-- Treesitter
--------------------------------------------------------------------------------
vim.api.nvim_create_autocmd("User", {
  pattern = "TSUpdate",
  callback = function()
    require("nvim-treesitter.parsers").cython = {
      -- require("nvim-treesitter.parsers").pyrex = {
      install_info = {
        url = "https://github.com/b0o/tree-sitter-cython",
        -- revision = "HEAD", -- commit hash for revision to check out; HEAD if missing
        -- optional entries:
        branch = "master", -- only needed if different from default branch
        -- location = "parser", -- only needed if the parser is in subdirectory of a "monorepo"
        generate = false, -- only needed if repo does not contain pre-generated `src/parser.c`
        generate_from_json = false, -- only needed if repo does not contain `src/grammar.json` either
        queries = "queries", -- also install queries from given directory
      },
    }
    vim.treesitter.language.register("cython", { "pyx", "pxd", "pxi" })
    -- vim.treesitter.language.register("pyrex", { "pyx", "pxd", "pxi" })
    -- vim.filetype.add({
    --   extension = {
    --     pyx = "cython",
    --     pxd = "cython",
    --     pxi = "cython",
    --   },
    -- })
  end,
})
