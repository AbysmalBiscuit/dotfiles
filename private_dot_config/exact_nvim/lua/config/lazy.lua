local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

local is_manpage = vim.g.is_manpage

-- local general_disabled_plugins = {
--   "bufferline.nvim",
--   "mini.pairs",
-- }
local manpage_disabled_plugins = {
  "bufferline.nvim",
  "mini.pairs",

  "chezmoi.nvim",
  "chezmoi.vim",
  "conform.nvim",
  "lualine.nvim",
  "vim-dadbod-ui",
  "vim-dadbod-completion",
  "nvim-treesitter",
  "nvim-treesitter-textobjects",
  "ts-comments.nvim",
  "blink.cmp",
  "vimtex",
  "which-key.nvim",
  "noice.nvim",
  "snacks.nvim",
  "mini.ai",
  "flash.nvim",
}

---@type boolean|fun(self:LazyPlugin):boolean|nil
local cond_func = nil
local disabled_plugins = {
  "gzip",
  -- "matchit",
  -- "matchparen",
  -- "netrwPlugin",
  "tarPlugin",
  "tohtml",
  "tutor",
  "zipPlugin",
}
-- local disabled_extras = {}

if is_manpage then
  cond_func = function(plugin)
    -- table.insert(_G.plugins, plugin)
    -- if plugin.name:match(".*nack.*") then
    --   vim.notify(vim.inspect(plugin))
    -- end
    local plugin_name = plugin.name
    for i = 1, #manpage_disabled_plugins do
      if manpage_disabled_plugins[i] == plugin_name then
        disabled_plugins[i] = nil
        return false
      end
    end
    return true
  end

  disabled_plugins = {
    "editorconfig",
    "net",
    "spellfile",
    "rplugin",
    "shada",
    "osc52",
    "gzip",
    "matchit",
    "matchparen",
    "netrwPlugin",
    "tarPlugin",
    "tohtml",
    "tutor",
    "zipPlugin",
  }

  -- Mock global Snacks to not have to load it
  local function mock_function()
    local obj = {}
    obj.map = function()
      return obj
    end
    return obj
  end

  _G.Snacks = {
    scroll = {},
    keymap = {
      set = function(modes, lhs, rhs, opts)
        if opts["ft"] ~= nil then
          return
        end
        if type(mode) == "table" then
          for _, m in ipairs(mode) do
            vim.keymap.set(m, lhs, rhs, opts)
          end
          return
        end
        vim.keymap.set(modes, lhs, rhs, opts)
      end,
    },
    toggle = setmetatable({
      option = mock_function,
      diagnostics = mock_function,
      line_number = mock_function,
      treesitter = mock_function,
      dim = mock_function,
      animate = mock_function,
      indent = mock_function,
      scroll = mock_function,
      profiler = mock_function,
      profiler_highlights = mock_function,
      inlay_hints = mock_function,
      zoom = mock_function,
      zen = mock_function,
    }, {
      __call = mock_function,
    }),
  }

  -- local extras_to_kill = {
  --   "lazyvim.plugins.extras.dap.core",
  --   "lazyvim.plugins.extras.test.core",
  --   "lazyvim.plugins.extras.coding.blink",
  --   "lazyvim.plugins.extras.lang.typescript",
  --   "lazyvim.plugins.extras.editor.snacks_explorer",
  --   "lazyvim.plugins.extras.editor.snacks_picker",
  --   "lazyvim.plugins.extras.ai.sidekick",
  --   "lazyvim.plugins.extras.coding.mini-surround",
  --   "lazyvim.plugins.extras.coding.neogen",
  --   "lazyvim.plugins.extras.coding.yanky",
  --   "lazyvim.plugins.extras.dap.nlua",
  --   "lazyvim.plugins.extras.editor.dial",
  --   "lazyvim.plugins.extras.editor.harpoon2",
  --   "lazyvim.plugins.extras.editor.inc-rename",
  --   "lazyvim.plugins.extras.lang.clangd",
  --   "lazyvim.plugins.extras.lang.docker",
  --   "lazyvim.plugins.extras.lang.json",
  --   "lazyvim.plugins.extras.lang.markdown",
  --   "lazyvim.plugins.extras.lang.nushell",
  --   "lazyvim.plugins.extras.lang.python",
  --   "lazyvim.plugins.extras.lang.rust",
  --   "lazyvim.plugins.extras.lang.sql",
  --   "lazyvim.plugins.extras.lang.tex",
  --   "lazyvim.plugins.extras.lang.toml",
  --   "lazyvim.plugins.extras.lang.yaml",
  --   "lazyvim.plugins.extras.linting.eslint",
  --   "lazyvim.plugins.extras.ui.treesitter-context",
  --   "lazyvim.plugins.extras.util.chezmoi",
  --   "lazyvim.plugins.extras.util.dot",
  --   "lazyvim.plugins.extras.util.mini-hipatterns",
  -- }
  -- for _, name in ipairs(extras_to_kill) do
  --   table.insert(disabled_extras, { import = name, enabled = false })
  -- end
end

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- unpack(disabled_extras),
    -- override default LazyVim settings
    {
      "LazyVim/LazyVim",
      opts = {
        colorscheme = function() end,
      },
    },
    { "lazyvim.plugins.extras.lang.toml", enabled = false },
    -- import/override with your plugins
    { import = "plugins", cond = not is_manpage },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
    -- when running inside vscode for example
    ---@type boolean|fun(self:LazyPlugin):boolean|nil
    cond = cond_func,
  },
  git = {
    throttle = {
      enabled = true,
      rate = 5,
      duration = 1000,
    },
  },
  -- install = { colorscheme = { "catppuccin-mocha" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  rocks = { hererocks = true },
  performance = {
    cache = {
      enabled = true,
      -- disable_events = {},
    },
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = disabled_plugins,
    },
  },
})
