-- vim.cmd("ToggleBlinkRipgrep")

local home = vim.fn.expand("~")
local chezmoi_source = home .. "/.local/share/chezmoi"
local chezmoi_toml_tmpl_filetype = "chezmoi_toml.toml.chezmoitmpl"

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
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("chezmoi_group_custom1", { clear = false }),
  pattern = ".chezmoi.toml.tmpl",
  callback = function()
    local stderr_chunks = {}
    local env = vim.deepcopy(vim.fn.environ())
    if vim.g.is_wsl then
      env.PATH = env.PATH_CLEAN .. ":" .. env.PATH_WINDOWS
    end

    local has_command = ""
    if vim.g.is_windows then
      has_command =
        'chezmoi execute-template (Get-Content "$HOME/.local/share/chezmoi/.chezmoiscripts/windows/run_onchange_before_01-generate-has-cache.ps1.tmpl" -Raw) | Out-String | Invoke-Expression'
    else
      has_command =
        "chezmoi execute-template < ~/.local/share/chezmoi/.chezmoiscripts/run_before_generate-has-cache.sh.tmpl | sh"
    end
    local function run_has_cache()
      vim.fn.jobstart(has_command, {
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
      })
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
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("chezmoi_toml_tmpl", { clear = true }),
  once = true,
  pattern = "*/.chezmoi.toml.tmpl",
  callback = function(args)
    vim.b[args.buf].chezmoi_ts_lang = chezmoi_toml_tmpl_filetype
    vim.b[args.buf].chezmoi_ts_pending = nil
    vim.wo[0].foldmethod = "manual"
    vim.treesitter.start(args.buf, chezmoi_toml_tmpl_filetype)
    vim.bo[args.buf].filetype = chezmoi_toml_tmpl_filetype
    vim.schedule(function()
      vim.bo[args.buf].filetype = chezmoi_toml_tmpl_filetype
    end)
  end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("chezmoi_group_custom3", { clear = false }),
  pattern = "*/.chezmoidata/*tools.toml",
  callback = function()
    local sort_command = ""
    if vim.g.is_windows then
      sort_command =
        'chezmoi execute-template (Get-Content "$HOME/.local/share/chezmoi/.chezmoiscripts/run_onchange_before_00-sort-tools.sh.tmpl" -Raw) | Out-String | python3'
    else
      sort_command = "chezmoi execute-template < ~/.local/share/chezmoi/.chezmoiscripts/run_before_generate-has-cache.sh.tmpl | "
        .. vim.g.python3_host_prog
    end
    local stderr_chunks = {}
    vim.fn.jobstart(sort_command, {
      stderr_buffered = true,
      on_stderr = function(_, data)
        if data then
          vim.list_extend(stderr_chunks, data)
          reload_buffers()
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            vim.notify("tools.toml sorted")
            local name = vim.api.nvim_buf_get_name(0)
            if name ~= "" and string.match(name, ".*tools%.toml") then
              vim.api.nvim_buf_call(0, function()
                vim.cmd("edit!")
              end)
            end
          else
            vim.notify("sorting tools.toml failed", vim.log.levels.ERROR)
            local msg = table.concat(stderr_chunks, "\n")
            vim.notify(msg, vim.log.levels.ERROR)
          end
        end)
      end,
    })
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
-- Treesitter
--------------------------------------------------------------------------------

local gotmpl_filetypes = { "go", "gomod", "gowork", "gotmpl" }
local chezmoi_filetypes = {
  "bash",
  "conf",
  "fish",
  "gitconfig",
  "ini",
  "json",
  "jsonc",
  "nu",
  "powershell",
  "ps1",
  "python",
  "sh",
  "toml",
  "yaml",
  "zsh",
}
local ft_to_parser = {
  sh = "bash",
}

-- Read query source files for a treesitter language
local function get_query_source(lang, query_name)
  local files = vim.treesitter.query.get_files(lang, query_name)
  if #files == 0 then
    return nil
  end
  local sources = {}
  for _, file in ipairs(files) do
    table.insert(sources, table.concat(vim.fn.readfile(file), "\n"))
  end
  return table.concat(sources, "\n")
end

-- Cache base gotmpl queries once
local propagated_queries = { "highlights", "folds", "indents", "locals" }
local gotmpl_query_cache = {}
local ts_lang_names = {}
local gotmpl_parser_path = vim.api.nvim_get_runtime_file("parser/gotmpl.so", false)[1]
  or vim.api.nvim_get_runtime_file("parser/gotmpl.dll", false)[1]
for _, name in ipairs(propagated_queries) do
  gotmpl_query_cache[name] = get_query_source("gotmpl", name)
end
-- Verify folds query exists
-- local folds_q = gotmpl_query_cache["folds"]
-- vim.schedule(function()
-- vim.defer_fn(function()
-- if folds_q then
-- vim.notify("folds query exists for " .. chezmoi_toml_tmpl_filetype, "info")
-- else
-- vim.notify("folds query is NIL", "info")
-- end
-- end, 5000)
-- end)

-- Register a per-filetype gotmpl variant with its own injection
for _, filetype in ipairs(chezmoi_filetypes) do
  local compound_ft = filetype .. ".chezmoitmpl"
  local ts_lang = "gotmpl_" .. filetype
  local inject_lang = ft_to_parser[filetype] or filetype

  table.insert(ts_lang_names, ts_lang)

  vim.treesitter.language.add(ts_lang, {
    path = gotmpl_parser_path,
    symbol_name = "gotmpl",
  })

  -- Map the compound filetype to our variant language
  vim.treesitter.language.register(ts_lang, compound_ft)

  for _, name in ipairs(propagated_queries) do
    if gotmpl_query_cache[name] then
      vim.treesitter.query.set(ts_lang, name, gotmpl_query_cache[name])
    end
  end

  vim.treesitter.query.set(
    ts_lang,
    "injections",
    string.format('((text) @injection.content (#set! injection.combined) (#set! injection.language "%s"))', inject_lang)
  )

  table.insert(gotmpl_filetypes, ts_lang)
  table.insert(gotmpl_filetypes, ts_lang .. ".chezmoitmpl")
  table.insert(gotmpl_filetypes, compound_ft)
  table.insert(gotmpl_filetypes, compound_ft .. ".chezmoitmpl")
  table.insert(gotmpl_filetypes, ts_lang .. "." .. compound_ft)
end

-- Add the .chezmoi.toml.tmpl special filetype
vim.treesitter.language.add(chezmoi_toml_tmpl_filetype, {
  path = gotmpl_parser_path,
  symbol_name = "gotmpl",
})
vim.treesitter.language.register(chezmoi_toml_tmpl_filetype, chezmoi_toml_tmpl_filetype)

table.insert(gotmpl_filetypes, chezmoi_toml_tmpl_filetype)

for _, name in ipairs(propagated_queries) do
  if gotmpl_query_cache[name] then
    vim.treesitter.query.set(chezmoi_toml_tmpl_filetype, name, gotmpl_query_cache[name])
  end
end

vim.treesitter.query.set(
  chezmoi_toml_tmpl_filetype,
  "injections",
  '((text) @injection.content (#set! injection.combined) (#set! injection.language "toml"))'
)

vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function(ev)
    local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ev.buf), ":t")
    local ft = vim.bo[ev.buf].filetype
    if fname:match("^modify_") and ft ~= "" and not ft:match("chezmoitmpl") then
      vim.b[ev.buf].chezmoi_ts_pending = true
      vim.bo[ev.buf].filetype = ft .. ".chezmoitmpl"
    end
  end,
})

-- Plain .tmpl files default to base gotmpl
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  pattern = "*.tmpl",
  callback = function(ev)
    vim.b[ev.buf].chezmoi_ts_pending = true
    vim.b[ev.buf].chezmoi_ts_lang = "gotmpl"
  end,
})

-- Compound filetypes get their specific variant
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*.chezmoitmpl",
  callback = function(ev)
    local ft = vim.bo[ev.buf].filetype
    local base = ft:match("^([^%.]+)%.chezmoitmpl$")
    if base then
      local ts_lang = "gotmpl_" .. base
      vim.b[ev.buf].chezmoi_ts_lang = ts_lang
      vim.b[ev.buf].chezmoi_ts_pending = nil
      -- Single clean start — no stop/start race
      vim.treesitter.start(ev.buf, ts_lang)
    end
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

  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == "" then
      return
    end
    local chezmoi_source = vim.fn.expand("~") .. "/.local/share/chezmoi"
    if vim.startswith(fname, chezmoi_source) then
      if fname:match("%.tmpl$") or fname:match("%.go$") then
        on_dir(chezmoi_source)
      end
      return
    end
    local root = require("lspconfig.util").root_pattern("go.work", "go.mod", ".git")(fname)
    if root then
      on_dir(root)
    end
  end,
})

vim.lsp.config("pyrefly", {
  filetypes = { "python", "python.chezmoitmpl", "python.chezmoitmpl.chezmoitmpl" },
})

vim.lsp.config("bashls", {
  filetypes = {
    "bash",
    "bash.chezmoitmpl",
    "bash.chezmoitmpl.chezmoitmpl",
    "zsh",
    "zsh.chezmoitmpl",
    "zsh.chezmoitmpl.chezmoitmpl",
    "sh",
    "sh.chezmoitmpl",
    "sh.chezmoitmpl.chezmoitmpl",
  },
})

-- vim.lsp.config("taplo", {
-- filetypes = { "toml", "toml.chezmoitmpl" },
-- })

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
require("gotmpl_comment").setup({ buffer = false, silent = true })

--------------------------------------------------------------------------------
-- Highlights
--------------------------------------------------------------------------------
vim.api.nvim_set_hl(0, "LspReferenceRead", {})

for _, ts_lang in ipairs(ts_lang_names) do
  vim.api.nvim_set_hl(0, "@function." .. ts_lang, { link = "@function.gotmpl" })
end
