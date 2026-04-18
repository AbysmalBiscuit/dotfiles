-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- /home/lev/.config/nvim/lua/config/options.lua
-- /home/lev/.config/nvim/lua/config

local o = vim.o
local g = vim.g
local go = vim.go
local augroup = vim.api.nvim_create_augroup

local has_display = vim.env.DISPLAY ~= nil or vim.env.WAYLAND_DISPLAY ~= nil

--------------------------------------------------------------------------------
-- environment setup
--------------------------------------------------------------------------------
-- set python3_host_prog if available
-- this speeds up loading
if vim.env.PYTHON3_HOST_PROG ~= nil then
  g.python3_host_prog = vim.env.PYTHON3_HOST_PROG
end

---@type boolean Variable to track compiler awareness state
g.has_nightly_rust = vim.env.HAS_NIGHTLY_RUST == "true"

if not g.has_nightly_rust and vim.fn.executable(vim.fn.expand("~/.cargo/bin/rustup")) == 1 then
  local openPop = assert(io.popen("rustup toolchain list", "r"))
  local output = openPop:read("*all")
  openPop:close()
  g.has_nightly_rust = string.match(output, ".*nightly.*") ~= nil
end

---@type boolean Variable to track if has fish shell and ocargo function
g.has_ocargo = vim.env.HAS_OCARGO == "true"

if not g.has_ocargo and g.has_nightly_rust and not vim.g.is_windows and vim.fn.executable("fish") == 1 then
  local openPop = assert(io.popen("fish --command 'functions --names'", "r"))
  local output = openPop:read("*all")
  openPop:close()
  g.has_ocargo = string.match(output, ".* ocargo.*") ~= nil
end

---@type boolean Tracks if macOS
g.is_macos = vim.fn.has("macunix") == 1 or vim.env.OS == "darwin"
g.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
g.is_linux = vim.fn.has("unix") == 1
g.is_wsl = vim.fn.has("wsl") == 1

--------------------------------------------------------------------------------
-- Convenience functions
--------------------------------------------------------------------------------

---Convenience function to pretty print anything
---@param ... any
_G.pprint = function(...)
  local to_print = ""
  if type(...) == "table" then
    to_print = "{"
    for key, item in pairs(...) do
      to_print = to_print .. string.format(" %s = %s,", key, vim.inspect(item))
    end
    to_print = to_print .. "}"
  else
    to_print = ...
  end
  vim.notify(to_print)
end

_G.check_extmarks = function()
  for ns, ns_name in pairs(vim.api.nvim_get_namespaces()) do
    if ns_name:match("diagnostic") then
      vim.notify("Namespace:", ns, ns_name)
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[4] and mark[4].priority then
          vim.notify("  line:", mark[2], "priority:", mark[4].priority)
        end
      end
    end
  end
end

---Show current filetype
_G.current_ft = function()
  vim.cmd([[echo &filetype]])
end

-- leader keys
g.mapleader = " "
-- g.maplocalleader = "|"
g.maplocalleader = "\\"

-- disable netrw for other file browser plugins
g.loaded_netrw = 1
g.loaded_netrwPlugin = 1

--------------------------------------------------------------------------------
-- swapfile and undo
--------------------------------------------------------------------------------
o.smartindent = true
o.shiftwidth = 4

o.wrap = false
o.exrc = true
o.secure = true

--------------------------------------------------------------------------------
-- swapfile and undo
--------------------------------------------------------------------------------
o.swapfile = false
o.backup = false
o.updatetime = 50
o.undofile = true
o.undodir = vim.fn.expand("~/.vim/undodir")

--------------------------------------------------------------------------------
-- search
--------------------------------------------------------------------------------
o.hlsearch = true
o.incsearch = true

--------------------------------------------------------------------------------
-- editor appearance
--------------------------------------------------------------------------------
o.guifont =
  "Sarasa Fixed K,NanumGothicCoding,Symbols Nerd Font Mono,Symbols Nerd Font,MesloLGM Nerd Font Propo,Atkinson Hyperlegible Mono,Noto Sans Mono CJK KR,Noto Sans Mono CJK SC,Noto Sans Mono CJK HK,Noto Sans Mono CJK JP,Noto Sans Mono CJK TC,Font Awesome 6 Pro,Twemoji Mozilla:h12"
o.termguicolors = true
o.nu = true
o.relativenumber = true
o.scrolloff = 8
o.signcolumn = "yes"
g.indent_char = "▎"
o.winborder = "rounded"
-- o.winborder = "single"
-- o.isfname = o.isfname .. ",@-@"
vim.opt.isfname:append("@-@")

-- o.colorcolumn = "80,100,120"

-- vim.opt.foldmethod = "manual"
-- vim.opt.foldenable = false
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  group = augroup("config_VimEnter_autocmds", { clear = true }),
  callback = function()
    -- Load Catppuccin for UI elements
    -- vim.cmd.colorscheme("catppuccin-mocha")
    if vim.fn.filereadable(vim.fn.expand("~/.config/nvim/colors/abc")) == 1 then
      -- vim.cmd.colorscheme("abc_merge")
      require("colors").load(true)
    else
      -- vim.notify("abc_merge theme not found!", vim.log.levels.ERROR)
      vim.notify("abc theme not found!", vim.log.levels.ERROR)
    end

    -- vim.opt.foldmethod = "expr"
    -- vim.opt.foldenable = true
    --     vim.cmd("VirtColumnEnable")
  end,
})

--------------------------------------------------------------------------------
-- set to 0 to make markdown indents follow global rules
--------------------------------------------------------------------------------
vim.g.markdown_recommended_style = 0

--------------------------------------------------------------------------------
-- spell
--------------------------------------------------------------------------------
vim.spelllang = "en_us"
o.ignorecase = true
o.smartcase = true
o.cursorline = true

--------------------------------------------------------------------------------
-- vimtex
--------------------------------------------------------------------------------
vim.g.vimtex_quickfix_enabled = 0
vim.g.vimtex_syntax_conceal_disable = 1

--------------------------------------------------------------------------------
-- clipboard
--------------------------------------------------------------------------------

-- vim.notify("here", "error")
-- print("here", "error")
vim.api.nvim_create_autocmd({ "VimEnter" }, {
  once = true,
  callback = function()
    if g.is_windows or g.is_wsl then
      if g.is_wsl then
        if vim.fn.executable("wl-copy") == 0 then
          vim.notify(
            "Install the 'wl-clipboard' package to get better clipboard performance on WSL.",
            vim.log.levels.WARN
          )
        else
          vim.g.clipboard = {
            name = "wl-clipboard (wsl)",
            copy = {
              ["+"] = "wl-copy --foreground --type text/plain",
              ["*"] = "wl-copy --foreground --primary --type text/plain",
            },
            paste = {
              ["+"] = function()
                return vim.fn.systemlist('wl-paste --no-newline|sed -e "s/\r$//"', { "" }, 1) -- '1' keeps empty lines
              end,
              ["*"] = function()
                return vim.fn.systemlist('wl-paste --primary --no-newline|sed -e "s/\r$//"', { "" }, 1)
              end,
            },
            cache_enabled = true,
          }
        end
      elseif vim.fn.executable("win32yank.exe") == 1 then
        vim.g.clipboard = {
          name = "win32yank.exe",
          copy = {
            ["+"] = "win32yank.exe -i --crlf",
            ["*"] = "win32yank.exe -i --crlf",
          },
          paste = {
            ["+"] = "win32yank.exe -o --lf",
            ["*"] = "win32yank.exe -o --lf",
          },
        }
        -- elseif vim.env.WIN32YANK ~= nil then
        --   vim.g.clipboard = {
        --     name = "wl-clipboard (wsl)",
        --     copy = {
        --       ["+"] = "wl-copy --foreground --type text/plain",
        --       ["*"] = "wl-copy --foreground --primary --type text/plain",
        --     },
        --     paste = {
        --       ["+"] = function()
        --         return vim.fn.systemlist('wl-paste --no-newline|sed -e "s/\r$//"', { "" }, 1) -- '1' keeps empty lines
        --       end,
        --       ["*"] = function()
        --         return vim.fn.systemlist('wl-paste --primary --no-newline|sed -e "s/\r$//"', { "" }, 1)
        --       end,
        --     },
        --     cache_enabled = true,
        --   }
      end
    elseif g.is_macos then
      vim.g.clipboard = {
        copy = {
          ["+"] = "pbcopy",
          ["*"] = "pbcopy",
        },
        paste = {
          ["+"] = "pbpaste -Prefer txt",
          ["*"] = "pbpaste -Prefer txt",
        },
      }
    elseif vim.fn.has("unix") == 1 then
      if has_display then
        if vim.fn.executable("xclip") == 1 then
          vim.g.clipboard = {
            copy = {
              ["+"] = "xclip -selection clipboard",
              ["*"] = "xclip -selection clipboard",
            },
            paste = {
              ["+"] = "xclip -selection clipboard -o",
              ["*"] = "xclip -selection clipboard -o",
            },
          }
        elseif vim.fn.executable("xsel") == 1 then
          vim.g.clipboard = {
            copy = {
              ["+"] = "xsel --clipboard --input",
              ["*"] = "xsel --clipboard --input",
            },
            paste = {
              ["+"] = "xsel --clipboard --output",
              ["*"] = "xsel --clipboard --output",
            },
          }
        end
      else
        local osc52 = require("vim.ui.clipboard.osc52")
        local last_regtype = {
          ["+"] = "v",
          ["*"] = "v",
        }

        local function copy_reg(reg)
          local osc52_copy = osc52.copy(reg)
          return function(lines, regtype)
            vim.fn.setreg("", table.concat(lines, "\n"), regtype)

            last_regtype[reg] = regtype

            osc52_copy(lines)
          end
        end

        vim.g.clipboard = {
          name = "OSC 52 with register sync",
          copy = {
            ["+"] = copy_reg("+"),
            ["*"] = copy_reg("*"),
          },
          paste = {
            ["+"] = function()
              local reg = vim.fn.getreg("", 1, true)
              if last_regtype["+"] == "V" then
                table.insert(reg, "")
              end
              return reg, last_regtype["+"]
            end,
            ["*"] = function()
              local reg = vim.fn.getreg("", 1, true)
              if last_regtype["+"] == "V" then
                table.insert(reg, "")
              end
              return reg, last_regtype["*"]
            end,
          },
        }
      end
    end
    vim.o.clipboard = "unnamedplus"
  end,
  desc = "Lazy load clipboard",
})

--------------------------------------------------------------------------------
-- WSL specific settings
--------------------------------------------------------------------------------
if g.is_wsl then
  vim.g.vimtex_view_method = "zathura"
  vim.g.vimtex_view_general_viewer = "zathura"
  vim.g.vimtex_view_automatic = 1
  vim.g.vimtex_view_enabled = 1
  vim.g.tex_flavor = "latex"
  -- vim.g.vimtex_latexmk_continuous = 1

  vim.env.PATH = vim.env.PATH .. ":/mnt/c/Program Files/WezTerm"
end

--------------------------------------------------------------------------------
-- windows specific settings
--------------------------------------------------------------------------------
if g.is_windows then
  -- Windows-specific settings
  if LazyVim ~= nil then
    LazyVim.terminal.setup("pwsh")
  elseif vim.fn.executable("C:/Program Files/PowerShell/7/pwsh.exe") == 1 then
    o.shell = "pwsh"
    o.shellcmdflag =
      "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;"
    o.shellredir = "-RedirectStandardOutput %s -NoNewWindow -Wait"
    o.shellpipe = "2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode"
    o.shellquote = ""
    o.shellxquote = ""
  elseif vim.fn.executable("powershell.exe") == 1 then
    o.shell = "powershell"
    -- o.shellcmdflag = "-command"
    o.shellcmdflag =
      "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;"
    o.shellredir = "-RedirectStandardOutput %s -NoNewWindow -Wait"
    o.shellpipe = "2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode"
    -- o.shellquote = '"'
    -- o.shellxquote = ""
  else
    o.shell = "cmd"
  end
end

--------------------------------------------------------------------------------
-- macOS specific settings
--------------------------------------------------------------------------------
if g.is_macos then
  vim.keymap.set({ "x", "n", "s" }, "<D-s>", "<cmd>w<cr><esc>", { desc = "Save File" })
  vim.keymap.set("i", "<D-s>", "<cmd>w<CR><esc>i", { desc = "Save File" })
  -- vim.keymap.set({ "t", "v" }, "<D-c>", '"+y', { desc = "Copy" })
  -- Copy from visual mode.
  vim.keymap.set("v", "<D-c>", '"+y', { desc = "Copy" })
  -- Paste in normal or in visual (to replace selection).
  vim.keymap.set({ "n", "v" }, "<D-v>", '"+p', { desc = "Paste" })
  -- Paste clipboard at cursor position from insert mode.
  vim.keymap.set("i", "<D-v>", "<C-r>+", { desc = "Paste" })
  -- vim.keymap.set({ "i", "n", "t", "v" }, "<D-v>", "+p<CR>", { desc = "Paste", noremap = true, silent = true })
  -- vim.keymap.set({ "!", "t", "v" }, "<D-v>", "<C-R>+", { desc = "Paste", noremap = true, silent = true })
  -- vim.keymap.set("v", "<D-c>", '"+y', { desc = "Copy", noremap = false, silent = true })
  -- vim.keymap.set("t", "<D-c>", [[<C-\><C-n>"+y]], { desc = "Copy", noremap = true, silent = true })

  -- vimtex options
  -- vim.g.vimtex_view_method = "zathura"
  -- vim.g.vimtex_view_forward_search_on_start = true
  vim.g.vimtex_view_method = "skim" -- Use Skim as the viewer
  vim.g.vimtex_view_skim_sync = 1 -- Enable Skim sync
  vim.g.vimtex_view_skim_activate = 1 -- Automatically activate Skim window
  vim.g.vimtex_compiler_method = "latexmk" -- Use latexmk for compilation
  -- vim.g.vimtex_grammar_vlty = {
  --   -- lt_directory = "/usr/local/Cellar/languagetool/6.6/libexec/",
  --   lt_command = "languagetool-server",
  --   server = "my",
  --   show_suggestions = 1,
  -- }
  -- vim.g.vimtex_grammar_textidote = {
  --   jar = "/usr/local/Cellar/textidote/0.8.3/libexec/textidote.jar",
  --   args = "--check en --read-all",
  -- }
end

--------------------------------------------------------------------------------
-- neovide settings
--------------------------------------------------------------------------------
if g.neovide then
  -- vim.g.indent_char = "│"
  if g.is_macos then
    vim.o.guifont =
      "Sarasa Fixed K,NanumGothicCoding,Symbols Nerd Font Mono,Symbols Nerd Font,MesloLGM Nerd Font Propo,Atkinson Hyperlegible Mono,Noto Sans Mono CJK KR,Noto Sans Mono CJK SC,Noto Sans Mono CJK HK,Noto Sans Mono CJK JP,Noto Sans Mono CJK TC,Font Awesome 6 Pro,Twemoji Mozilla:h14"
    vim.g.neovide_refresh_rate = 60
    vim.o.linespace = -2
    vim.keymap.set({ "x", "n", "s" }, "<D-s>", "<cmd>w<cr><esc>", { desc = "Save File" })
    vim.keymap.set("i", "<D-s>", "<cmd>w<CR><esc>i", { desc = "Save File" })
    vim.keymap.set({ "t", "v" }, "<D-c>", '"+y', { desc = "Copy" })
    vim.keymap.set({ "n", "v", "t" }, "<D-v>", '"+P', { desc = "Paste" })
    vim.keymap.set("c", "<D-v>", "<C-R>+", { desc = "Paste command mode" })
    vim.keymap.set("i", "<D-v>", '<ESC>l"+Pli', { desc = "Paste in insert mode" })
  else
    vim.o.guifont =
      "Sarasa Fixed K,NanumGothicCoding,Symbols Nerd Font Mono,Symbols Nerd Font,MesloLGM Nerd Font Propo,Atkinson Hyperlegible Mono,Noto Sans Mono CJK KR,Noto Sans Mono CJK SC,Noto Sans Mono CJK HK,Noto Sans Mono CJK JP,Noto Sans Mono CJK TC,Font Awesome 6 Pro,Twemoji Mozilla:h13"
    vim.g.neovide_refresh_rate = 117
    vim.o.linespace = -1
  end
  if g.is_wsl then
    local clean_path = {}
    local wsl_mnt_prefix = "/mnt/"
    -- for part in string.gmatch(vim.env.PATH, "[^:]+") do
    --   if part:sub(1, 5) ~= wsl_mnt_prefix then
    --     table.insert(clean_path, part)
    --   end
    -- end
    local clean = table.concat(clean_path, ":")
    vim.env.PATH = clean
  end
  vim.g.neovide_scale_factor = 1.0
  vim.g.neovide_scroll_animation_length = 0
  vim.g.neovide_scroll_animation_far_lines = 0
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_cursor_antialiasing = true
end

--------------------------------------------------------------------------------
-- session management
--------------------------------------------------------------------------------
-- vim.o.sessionoptions = "buffers,curdir,folds,globals,help,localoptions,skiprtp,tabpages,winsize,winpos"

vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup("config_Persistence", { clear = true }),
  callback = function()
    -- NOTE: Before restoring the session, check:
    -- 1. No arg passed when opening nvim, means no `nvim --some-arg ./some-path`
    -- 2. No pipe, e.g. `echo "Hello world" | nvim`
    -- 3. Not opening a man page

    -- vim.notify("vim.fn.argc() " .. vim.inspect(vim.fn.argc()))
    -- vim.notify("vim.g.started_with_stdin " .. string.format("%s", vim.g.started_with_stdin))
    -- vim.notify("vim.v.argv " .. string.format("%s", vim.inspect(vim.v.argv)))
    if vim.fn.argc() == 0 and not vim.g.started_with_stdin and not g.is_manpage then
      require("persistence").load()
    -- elseif vim.tbl_contains(vim.v.argv, "--create-persistence-session") then
    --   require("persistence").save()
    else
      for _, item in ipairs(vim.v.argv) do
        if string.match(item, ".*/fish%..+/command%-line%.fish") then
          require("persistence").stop()
          break
        end
      end
    end
  end,
  -- HACK: need to enable `nested` otherwise the current buffer will not have a filetype (no syntax)
  nested = true,
})

-- vim.api.nvim_create_autocmd("LspAttach", {
--   group = augroup("config_Lsp", { clear = true }),
--   callback = function(args)
--     -- Enable inlay hints if they are supported
--     -- vim.lsp.inlay_hint.enable(true, { buffer = args.buf })
--
--     -- vim.keymap.set("n", "<C-.>", function()
--     --   local curr_row = vim.api.nvim_win_get_cursor(0)[1]
--     --   vim.lsp.buf.code_action({ ["range"] = { ["start"] = { curr_row, 0 }, ["end"] = { curr_row, 120 } } })
--     -- end, { buffer = args.buf, desc = "Code Action" })
--     --
--     -- vim.keymap.set("n", "<M-.>", function()
--     --   local curr_row = vim.api.nvim_win_get_cursor(0)[1]
--     --   vim.lsp.buf.code_action({ ["range"] = { ["start"] = { curr_row, 0 }, ["end"] = { curr_row, 120 } } })
--     -- end, { buffer = args.buf, desc = "Code Action" })
--
--     -- Disable syntax highlighting
--     -- local client = vim.lsp.get_client_by_id(args.data.client_id)
--     -- if client ~= nil then
--     --   client.server_capabilities.semanticTokensProvider = nil
--     -- end
--   end,
-- })

-- vim.api.nvim_create_autocmd("CursorHold", {
--   group = vim.api.nvim_create_augroup("DiagnosticsPopup", { clear = true }),
--   callback = function()
--     vim.diagnostic.open_float(nil, { focus = false })
--   end,
-- })

-- vim.api.nvim_create_autocmd("VimEnter", {
--   desc = "Auto select virtualenv Nvim open",
--   pattern = "*",
--   callback = function()
--     local venv = vim.fn.findfile("pyproject.toml", vim.fn.getcwd() .. ";")
--
--     if venv ~= "" then
--       require("venv-selector").retrieve_from_cache()
--     end
--   end,
--   once = true,
-- })

--------------------------------------------------------------------------------
-- LazyVim options
--------------------------------------------------------------------------------
-- vim.g.lazyvim_blink_main = true
g.blink_cmp = true
o.smoothscroll = false
g.snacks_animate = false
g.snacks_animate_dim = false
g.snacks_animate_indent = false
g.snacks_scroll = false

--------------------------------------------------------------------------------
-- Early exit if manpage
--------------------------------------------------------------------------------
-- if g.is_manpage then
--   return
-- end

--------------------------------------------------------------------------------
-- LazyVim root dir detection
--------------------------------------------------------------------------------
-- Each entry can be:
-- * the name of a detector function like `lsp` or `cwd`
-- * a pattern or array of patterns like `.git` or `lua`.
-- * a function with signature `function(buf) -> string|string[]`
-- vim.g.root_spec = { "lsp", { ".git", "lua" }, "cwd" }
vim.g.root_spec = { "lsp", { ".git", "lua" }, "cwd", ".venv", "pyproject.toml" }

-- LSP Server to use for Python.
-- Set to "basedpyright" to use basedpyright instead of pyright.
-- vim.g.lazyvim_python_lsp = "pylyzer"
-- vim.g.lazyvim_python_lsp = "basedpyright"
vim.g.lazyvim_python_lsp = "pyrefly"
-- Set to "ruff_lsp" to use the old LSP implementation version.
vim.g.lazyvim_python_ruff = "ruff"

-- vim.o.grepprg = "rg --vimgrep --follow"
-- vim.o.grepprg =
--   "rg -u --vimgrep --follow --hidden --no-heading --with-filename --line-number --column --smart-case --glob=!**/.git/* --glob=!**/.idea/* --glob=!**/.vscode/* --glob=!**/build/* --glob=!**/dist/* --glob=!**/yarn.lock --glob=!**/package-lock.json"

--------------------------------------------------------------------------------
-- LSP
--------------------------------------------------------------------------------
-- vim.lsp.enable("ty")
-- vim.lsp.enable({ "basedpyright" })
vim.lsp.enable({ "ltex_plus" })
vim.lsp.enable({ "pyrefly" })
vim.lsp.enable({ "cspell_ls" })
vim.lsp.enable({ "gdscript" })
vim.lsp.enable({ "gdshader_lsp" })
vim.lsp.enable({ "gdshader_lsp_cpp" })
-- vim.lsp.set_log_level("debug")
-- vim.lsp.enable({ "taplo" })
-- vim.lsp.enable({ "starlark_rust" })
-- vim.lsp.enable({ "bzl" })

-- tihs bda spel
-- vim.o.list = false
-- vim.o.listchars = {
--   tab = ">-",
--   nbsp = "%",
--   trail = "-",
--   eol = "¶",
--   space = "-",
-- }

--------------------------------------------------------------------------------
-- Filetypes
--------------------------------------------------------------------------------

-- vim.filetype.add({
--   extension = {
--     foo = "fooscript",
--     bar = function(path, bufnr)
--       if some_condition() then
--         return "barscript",
--           function(bufnr)
--             -- Set a buffer variable
--             vim.b[bufnr].barscript_version = 2
--           end
--       end
--       return "bar"
--     end,
--   },
--   filename = {
--     [".foorc"] = "toml",
--     ["/etc/foo/config"] = "toml",
--   },
--   pattern = {
--     [".*/etc/foo/.*"] = "fooscript",
--     -- Using an optional priority
--     [".*/etc/foo/.*%.conf"] = { "dosini", { priority = 10 } },
--     -- A pattern containing an environment variable
--     ["${XDG_CONFIG_HOME}/foo/git"] = "git",
--     [".*README.(%a+)"] = function(path, bufnr, ext)
--       if ext == "md" then
--         return "markdown"
--       elseif ext == "rst" then
--         return "rst"
--       end
--     end,
--   },
-- })

vim.filetype.add({
  extension = {
    -- ato = "ato",
    -- bean = "bean",
    -- ato = "atopile",
    ttl = "turtle",
    -- jsx = "javascriptreact",
    -- tsx = "typescriptreact",
    jsonl = "json",
    star = "bzl",
    yql = "yql",
    profile = "profile",
    -- kbd = "lisp",

    pyx = "cython",
    pxd = "cython",
    pxi = "cython",
    -- pyx = "pyrex",
    -- pxd = "pyrex",
    -- pxi = "pyrex",

    -- godot projects
    godot = "gdresource",
    tscn = "gdresource",
    tres = "gdresource",
    import = "gdresource",
    uid = "gduid",
    glb = "glb",
  },
  filename = {
    ["ltex.hiddenFalsePositives.en-US.txt"] = "json",
    [".chezmoi.toml.tmpl"] = "chezmoi_toml.toml.chezmoitmpl",
    [".bash_aliases"] = "bash",
    [".bash_env"] = "bash",
    [".bash_make"] = "bash",
    [".bash_prompt"] = "bash",
    [".bash_logout"] = "bash",
  },
  pattern = {
    [".*/*%.als"] = "alloy",
    [".*_bash_aliases"] = "bash",
    [".*_bash_env"] = "bash",
    [".*_bash_make"] = "bash",
    [".*_bash_profile"] = "bash",
    [".*_bash_prompt"] = "bash",
    [".*_bash_logout"] = "bash",
    -- ["%.bash_.*"] = "bash",
    [".*%.ps1%.tmpl"] = "ps1.chezmoitmpl",
    -- [".*%.toml.tmpl"] = "toml",
  },
})

--------------------------------------------------------------------------------
-- Detect if specific plugins are installed
--------------------------------------------------------------------------------
g.has_tabnine = LazyVim.has("tabnine.nvim")

--------------------------------------------------------------------------------
-- Treesitter
--------------------------------------------------------------------------------

vim.treesitter.language.register("cython", { "pyx", "pxd", "pxi" })

-- Patching gdscript
local function patch_parsers()
  package.loaded["nvim-treesitter.parsers"] = nil
  package.preload["nvim-treesitter.parsers"] = nil
  local parsers = require("nvim-treesitter.parsers")
  parsers.gdscript.install_info.revision = "89e66b6bdc002ab976283f277cbb48b780c5d0e9"
  parsers.gdscript.install_info.url = "https://github.com/PrestonKnopp/tree-sitter-gdscript"
  package.preload["nvim-treesitter.parsers"] = patch_parsers
  return parsers
end

package.preload["nvim-treesitter.parsers"] = patch_parsers

local query_names = { "highlights", "indents", "injections", "folds", "locals" }
for _, name in ipairs(query_names) do
  local path = vim.fn.stdpath("config") .. "/after/queries/gdscript/" .. name .. ".scm"
  local f = io.open(path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    vim.treesitter.query.set("gdscript", name, content)
  end
end
