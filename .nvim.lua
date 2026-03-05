-- vim.cmd("ToggleBlinkRipgrep")

local home = vim.fn.expand("~")
local chezmoi_source = home .. "/.local/share/chezmoi"

function reload_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and not vim.startswith(name, chezmoi_source) and vim.startswith(name, home) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit!")
        end)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Autocommands
--------------------------------------------------------------------------------
-- vim.api.nvim_create_autocmd("BufWritePost", {
--     pattern = ".chezmoi.toml.tmpl", -- filename or glob pattern
--     callback = function()
--         vim.fn.jobstart("chezmoi init", {
--             on_exit = function(_, code)
--                 if code == 0 then
--                     vim.notify("Command succeeded")
--                 else
--                     vim.notify("Command failed (exit " .. code .. ")", vim.log.levels.ERROR)
--                 end
--             end,
--         })
--     end,
-- })
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("chezmoi_group_custom1", { clear = false }),
  pattern = ".chezmoi.toml.tmpl",
  callback = function()
    local stderr_chunks = {}
    local env = vim.deepcopy(vim.fn.environ())
    if vim.g.is_wsl then
      env.PATH = env.PATH_CLEAN .. ":" .. env.PATH_WINDOWS
    end

    local function run_has_cache()
      vim.fn.jobstart(
        "chezmoi execute-template < ~/.local/share/chezmoi/.chezmoiscripts/run_before_generate-has-cache.sh.tmpl | sh",
        {
          env = env,
          on_exit = function(_, code)
            vim.schedule(function()
              if code == 0 then
                vim.notify("has cache rebuilt")
              else
                vim.notify("has cache rebuild failed", vim.log.levels.ERROR)
              end
            end)
          end,
        }
      )
    end

    vim.fn.jobstart("chezmoi init", {
      stderr_buffered = true,
      env = env,
      on_stderr = function(_, data)
        if data then
          vim.list_extend(stderr_chunks, data)
          reload_buffers()
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            vim.notify("chezmoi init succeeded")
            run_has_cache()
          else
            vim.notify("chezmoi init failed", vim.log.levels.ERROR)
            local msg = table.concat(stderr_chunks, "\n")
            vim.notify(msg, vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("chezmoi_group_custom2", { clear = false }),
  callback = function()
    vim.schedule(reload_buffers)
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("chezmoi_toml_tmpl", { clear = true }),
  pattern = "toml.chezmoitmpl",
  callback = function(args)
    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t")
    if filename == ".chezmoi.toml.tmpl" then
      vim.bo[args.buf].filetype = "chezmoi_toml.toml.chezmoitmpl"
    end
  end,
})

--------------------------------------------------------------------------------
-- Snacks
--------------------------------------------------------------------------------
local snacks_sources = {
  "files",
  "explorer",
  "grep",
  "grep_word",
  "grep_buffers",
  "lsp_references",
  "lsp_definitions",
  "lsp_declarations",
  "lsp_implementations",
  "lsp_symbols",
  "lsp_workspace_symbols",
}

for _, source_name in ipairs(snacks_sources) do
  local source = Snacks.config.picker.sources[source_name]
  if source ~= nil then
    ---@diagnostic disable-next-line: inject-field
    source.follow = true
    ---@diagnostic disable-next-line: inject-field
    source.hidden = true
  end
end

--------------------------------------------------------------------------------
-- Highlights
--------------------------------------------------------------------------------
vim.api.nvim_set_hl(0, "LspReferenceRead", {})

--------------------------------------------------------------------------------
-- Treesitter
--------------------------------------------------------------------------------

local gotmpl_filetypes = { "go", "gomod", "gowork", "gotmpl" }
local chezmoi_filetypes = {
  "bash",
  "sh",
  "fish",
  "toml",
  "conf",
  "ini",
  "gitconfig",
  "yaml",
  "json",
  "jsonc",
  "zsh",
  -- "nanorc",
}
local ft_to_parser = {
  sh = "bash",
}
local chezmoi_filetypes_postfixed = {}
for i = 1, #chezmoi_filetypes do
  local filetype = chezmoi_filetypes[i]
  local post_fixed = filetype .. ".chezmoitmpl"
  table.insert(chezmoi_filetypes_postfixed, post_fixed)
  table.insert(gotmpl_filetypes, post_fixed)
  vim.treesitter.language.register("gotmpl", post_fixed)
  if ft_to_parser[filetype] == nil then
    ft_to_parser[filetype] = filetype
  end
end

local function set_gotmpl_injections(lang)
  vim.treesitter.query.set(
    "gotmpl",
    "injections",
    string.format('((text) @injection.content (#set! injection.combined) (#set! injection.language "%s"))', lang)
  )
end

local orig_ts_start = vim.treesitter.start
vim.treesitter.start = function(buf, lang, ...)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if vim.b[buf].chezmoi_ts_lang then
    lang = vim.b[buf].chezmoi_ts_lang
  end
  return orig_ts_start(buf, lang, ...)
end

vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = { "*.tmpl" },
  callback = function(ev)
    -- Mark this buffer early, before filetype is even set
    vim.b[ev.buf].chezmoi_ts_lang = "gotmpl"
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "*.chezmoitmpl",
  callback = function(ev)
    local ft = vim.bo[ev.buf].filetype
    local base = ft:match("^(.+)%.chezmoitmpl$")
    local lang = ft_to_parser[base] or "bash"
    vim.b[ev.buf].chezmoi_base_parser = lang
    set_gotmpl_injections(lang)
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  pattern = "*.tmpl",
  callback = function(ev)
    vim.b[ev.buf].chezmoi_ts_lang = "gotmpl"
  end,
})

--------------------------------------------------------------------------------
-- LSP
--------------------------------------------------------------------------------

vim.lsp.config("gopls", {
  filetypes = gotmpl_filetypes,
  settings = {
    gopls = {
      templateExtensions = { "tmpl" },
    },
  },
})

-- local ignored_vtsls_codes = { [80001] = true }
-- local method = vim.lsp.protocol.Methods.textDocument_publishDiagnostics
--
-- vim.api.nvim_create_autocmd("LspAttach", {
--   callback = function(args)
--     local client = vim.lsp.get_client_by_id(args.data.client_id)
--
--     -- Only apply to vtsls
--     if client and client.name == "vtsls" then
--       client.handlers[method] = function(err, result, ctx, config)
--         if result.diagnostics then
--           local filtered = {}
--           for _, diagnostic in ipairs(result.diagnostics) do
--             if not ignored_vtsls_codes[diagnostic.code] then
--               table.insert(filtered, diagnostic)
--             end
--           end
--           result.diagnostics = filtered
--         end
--         -- Call the default handler with the filtered results
--         vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx)
--       end
--     end
--   end,
-- })

--------------------------------------------------------------------------------
-- gotmpl comments
--------------------------------------------------------------------------------
-- vim.api.nvim_create_autocmd("FileType", {
--     group = vim.api.nvim_create_augroup("gotmpl_comment", { clear = false }),
--     pattern = gotmpl_filetypes,
--     callback = function()
--         require("gotmpl_comment").setup()
--     end,
-- })
require("gotmpl_comment").setup({ buffer = false, silent = true })
