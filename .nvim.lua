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
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("chezmoi_group_custom3", { clear = false }),
  pattern = "*/.chezmoidata/*tools.toml",
  callback = function()
    local stderr_chunks = {}
    vim.fn.jobstart("chezmoi apply --include=scripts", {
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
-- Highlights
--------------------------------------------------------------------------------
vim.api.nvim_set_hl(0, "LspReferenceRead", {})

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
local gotmpl_parser_path = vim.api.nvim_get_runtime_file("parser/gotmpl.so", false)[1]
  or vim.api.nvim_get_runtime_file("parser/gotmpl.dll", false)[1]
for _, name in ipairs(propagated_queries) do
  gotmpl_query_cache[name] = get_query_source("gotmpl", name)
end

-- Register a per-filetype gotmpl variant with its own injection
for _, filetype in ipairs(chezmoi_filetypes) do
  local compound_ft = filetype .. ".chezmoitmpl"
  local ts_lang = "gotmpl_" .. filetype
  local inject_lang = ft_to_parser[filetype] or filetype

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

  table.insert(gotmpl_filetypes, compound_ft)
end

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
  -- root_dir = vim.fs.root(0, { ".git/" }),
  -- root_dir = function(bufnr, fname)
  -- if type(fname) ~= "string" then
  -- return nil
  -- end

  -- -- Filetype may not be set when root_dir is called, so check filename
  -- local dominated_file = fname:match("%.tmpl$")
  -- or fname:match("%.go$")
  -- or fname:match("go%.mod$")
  -- or fname:match("go%.work$")

  -- if not dominated_file then
  -- -- Fallback: check filetype if buffer exists
  -- local buf = (type(bufnr) == "number" and bufnr > 0) and bufnr or vim.fn.bufnr(fname)
  -- if buf < 1 then
  -- return nil
  -- end
  -- local ft = vim.bo[buf].filetype
  -- if not vim.tbl_contains({ "go", "gomod", "gowork", "gotmpl" }, ft) and not ft:match("%.chezmoitmpl$") then
  -- return nil
  -- end
  -- end

  -- local chezmoi_source = vim.fn.expand("~") .. "/.local/share/chezmoi"
  -- if vim.startswith(fname, chezmoi_source) then
  -- return chezmoi_source
  -- end
  -- return require("lspconfig.util").root_pattern("go.work", "go.mod", ".git")(fname)
  -- end,
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
-- vim.api.nvim_create_autocmd("FileType", {
--     group = vim.api.nvim_create_augroup("gotmpl_comment", { clear = false }),
--     pattern = gotmpl_filetypes,
--     callback = function()
--         require("gotmpl_comment").setup()
--     end,
-- })
require("gotmpl_comment").setup({ buffer = false, silent = true })
