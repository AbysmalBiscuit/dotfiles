-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

local cmdline_position = { row = "98%", col = "50%" }

local lazygit_os = {}
if vim.g.is_windows then
  lazygit_os = {
    edit = "lazygit-edit-nvim.cmd {{filename}}",
    editAtLine = "edit-nvim.cmd {{filename}}",
    editInTerminal = false,
  }
else
  lazygit_os = {
    editPreset = "nvim-remote",
  }
end

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
local picker_attrs = {
  "follow",
  "hidden",
  "ignored",
  "modified",
  -- regex = { icon = "R", value = false },
}
vim.api.nvim_create_user_command("SnacksPickerToggle", function(args)
  -- args = args or snacks_sources
  args = args or picker_attrs
  for _, source_name in ipairs(snacks_sources) do
    local source = Snacks.config.picker.sources[source_name]
    if source ~= nil then
      ---@diagnostic disable-next-line: inject-field
      -- source.follow = true
      for _, attr in ipairs(args) do
        if not source[attr] == nil then
          ---@diagnostic disable-next-line: inject-field
          source[attr] = true
        else
          source[attr] = false
        end
      end
    end
  end
end, {
  desc = "Toggle Snacks.picker settings",
  nargs = "*",
  ---@type fun(ArgLead: string, CmdLine: string, CursorPos: number): string[]
  complete = function(ArgLead, CmdLine, CursorPos)
    local args = vim.split(CmdLine, " ", { trimempty = true })
    local unused_args = {}
    for i = 1, #picker_attrs do
      local attr = picker_attrs[i]
      if not vim.list_contains(args, attr) then
        table.insert(unused_args, attr)
      end
    end
    return vim.tbl_filter(function(item)
      return item:find("^" .. ArgLead)
    end, unused_args)
  end,
})

-- vim.api.nvim_create_user_command("PickerToggleIgnored", function ()
--   local picker = require("snacks.picker").config
-- end)

---@type LazyPluginSpec[]
return {
  {
    "folke/snacks.nvim",
    -- priority = 1000,
    -- lazy = false,
    keys = {
      {
        "<leader>s'",
        function()
          Snacks.picker.registers()
        end,
        desc = "Registers",
      },
      {
        "<leader>sP",
        function()
          Snacks.picker.pickers()
        end,
        desc = "Pickers",
      },
      -- {
      --   "<leader>sr",
      --   function()
      --     Snacks.picker.resume()
      --   end,
      --   desc = "Resume",
      -- },
      {
        "<leader>uC",
        false,
      },
    },
    ---@type snacks.Config
    opts = {
      ---@type snacks.lazygit.Config
      lazygit = {
        config = {
          os = lazygit_os,
        },
      },
      explorer = {
        replace_netrw = false,
      },
      ---@type snacks.picker.Config
      picker = {
        follow = true,
        sources = {
          files = { follow = true, hidden = true },
          explorer = { follow = true },
          grep = { follow = true, hidden = true },
          grep_word = { follow = true, hidden = true },
          grep_buffers = { follow = true, hidden = true },
          lsp_references = { follow = true },
          lsp_definitions = { follow = true },
          lsp_declarations = { follow = true },
          lsp_implementations = { follow = true },
          lsp_symbols = { follow = true },
          lsp_workspace_symbols = { follow = true },
        },
        matcher = {
          -- frecency = true,
        },
        win = {
          input = {
            keys = {
              ["<C-c>"] = { "close", mode = { "i", "n" } },
              -- ["<Esc>"] = { "close", mode = { "n", "i" } },
              ["<PageUp>"] = { "list_scroll_up", mode = { "i", "n" } },
              ["<PageDown>"] = { "list_scroll_down", mode = { "i", "n" } },
              ["<Home>"] = { "preview_scroll_up", mode = { "i", "n" } },
              ["<End>"] = { "preview_scroll_down", mode = { "i", "n" } },
              ["<c-d>"] = { "inspect", mode = { "n", "i" } },
              ["<c-f>"] = { "toggle_follow", mode = { "i", "n" } },
              ["<c-h>"] = { "toggle_hidden", mode = { "i", "n" } },
              ["<c-i>"] = { "toggle_ignored", mode = { "i", "n" } },
              ["<c-m>"] = { "toggle_maximize", mode = { "i", "n" } },
              ["<c-p>"] = { "toggle_preview", mode = { "i", "n" } },
              ["<M-D-w>"] = { "cycle_win", mode = { "i", "n" } },
              ["<c-n>"] = { "cycle_win", mode = { "i", "n" } },
            },
          },
          list = {
            keys = {
              -- ["<Esc>"] = { "close", mode = { "n", "i" } },
              ["<PageUp>"] = { "list_scroll_up", mode = { "i", "n" } },
              ["<PageDown>"] = { "list_scroll_down", mode = { "i", "n" } },
              ["<Home>"] = { "preview_scroll_up", mode = { "i", "n" } },
              ["<End>"] = { "preview_scroll_down", mode = { "i", "n" } },
              ["<c-d>"] = { "inspect", mode = { "n", "i" } },
              ["<c-f>"] = { "toggle_follow", mode = { "i", "n" } },
              ["<c-h>"] = { "toggle_hidden", mode = { "i", "n" } },
              ["<c-i>"] = { "toggle_ignored", mode = { "i", "n" } },
              ["<c-m>"] = { "toggle_maximize", mode = { "i", "n" } },
              ["<c-p>"] = { "toggle_preview", mode = { "i", "n" } },
              ["<M-D-w>"] = { "cycle_win", mode = { "i", "n" } },
              ["<c-n>"] = { "cycle_win", mode = { "i", "n" } },
            },
          },
          preview = {
            keys = {
              ["<c-n>"] = "cycle_win",
            },
            wo = {
              conceallevel = 0,
              wrap = true,
            },
          },
        },

        -- previewers = {
        --   man_pager = vim.fn.executable("bat") == 1 and "col -bx | bat -l man -p " or nil,
        -- },
      },

      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      scroll = { enabled = false },

      ---@type snacks.indent.Config
      indent = {
        animate = {
          enabled = false,
        },
        indent = {
          enabled = true,
          -- hl = require("colors").rainbow_highlight,
          char = vim.g.indent_char,
        },
        scope = {
          enabled = true,
          underline = true,
          only_current = true,
          priority = 100,
          hl = require("colors").rainbow_highlight,
          char = vim.g.indent_char,
        },
        chunk = {
          -- when enabled, scopes will be rendered as chunks, except for the
          -- top-level scope which will be rendered as a scope.
          enabled = false,
          -- only show chunk scopes in the current window
          only_current = false,
          hl = "SnacksIndentChunk", ---@type string|string[] hl group for chunk scopes
          char = {
            corner_top = "┌",
            corner_bottom = "└",
            -- corner_top = "╭",
            -- corner_bottom = "╰",
            horizontal = "─",
            vertical = "│",
            arrow = ">",
          },
        },
      },

      -- notifier = {
      --   filter = function(notif)
      --     return notif.msg:find('^Decoration provider "win" %(ns=nvim.lsp.inlayhint%):') == nil
      --     -- return notif.msg == 'Decoration provider "win" (ns=nvim.lsp.inlayhint)'
      --     -- return true
      --   end,
      -- },
    },
    -- config = function(_, opts)
    --   require("snacks").setup(opts)
    -- end,
    -- config = function(_, opts)
    --   local notify = vim.notify
    --   require("snacks").setup(opts)
    --   -- HACK: restore vim.notify after snacks setup and let noice.nvim take over
    --   -- this is needed to have early notifications show up in noice history
    --   if LazyVim.has("noice.nvim") then
    --     vim.notify = notify
    --   end
    --
    -- end,
  },
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    keys = function(_, keys)
      local remove = {
        ["<c-f>"] = true,
        ["<c-b>"] = true,
      }
      for i = #keys, 1, -1 do
        if remove[keys[i][1]] then
          table.remove(keys, i)
        end
      end
      table.insert(keys, {
        "<c-t>",
        function()
          if not require("noice.lsp").scroll(4) then
            return "<c-f>"
          end
        end,
        silent = true,
        expr = true,
        desc = "Scroll Forward",
        mode = { "i", "n", "s" },
      })
      table.insert(keys, {
        "<c-p>",
        function()
          if not require("noice.lsp").scroll(-4) then
            return "<c-b>"
          end
        end,
        silent = true,
        expr = true,
        desc = "Scroll Backward",
        mode = { "i", "n", "s" },
      })
      return keys
    end,
    ---@type NoiceConfig
    opts = {
      presets = {
        lsp_doc_border = true,
        command_palette = {
          views = {
            cmdline_popup = {
              position = cmdline_position,
              size = {
                min_width = 60,
                width = "auto",
                height = "auto",
              },
            },
            cmdline_popupmenu = {
              position = {
                row = "90%",
                col = "50%",
              },
            },
          },
        },
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      extensions = {
        "mason",
        "nvim-dap-ui",
        "toggleterm",
      },
    },
    -- opts = function(_, opts)
    --   -- table.insert(opts.sections.lualine_b, 1, {
    --   --   -- indicate if a macro is being recorded
    --   --   require("noice").api.status.mode.get,
    --   --   cond = function()
    --   --     local mode = require("noice").api.status.mode.get()
    --   --     if mode then
    --   --       return mode:find("^recording") ~= nil
    --   --     end
    --   --     return false
    --   --   end,
    --   -- })
    --   -- table.insert(opts.extensions, "mason")
    --   table.insert(opts.extensions, "nvim-dap-ui")
    --   table.insert(opts.extensions, "toggleterm")
    --   return opts
    -- end,
  },
  {
    "lukas-reineke/virt-column.nvim",
    cmd = {
      "VirtColumnEnable",
      "VirtColumnDisable",
      "VirtColumnToggle",
    },
    event = "VeryLazy",
    enabled = true,
    opts = {
      enabled = true,
      char = "▕",
      highlight = "VirtColumn",
      virtcolumn = "+1,80,100,120",
      exclude = {
        filetypes = {
          "latex",
          "tex",
        },
      },
    },
    config = function(_, opts)
      local virt_column = require("virt-column")
      local virt_column_config = require("virt-column.config")
      virt_column.setup(opts)

      -- Create commands
      vim.api.nvim_create_user_command("VirtColumnEnable", function()
        virt_column.update({ enabled = true })
      end, { nargs = 0 })
      vim.api.nvim_create_user_command("VirtColumnDisable", function()
        virt_column.update({ enabled = false })
      end, { nargs = 0 })
      vim.api.nvim_create_user_command("VirtColumnToggle", function()
        virt_column.update({ enabled = not virt_column_config.config.enabled })
      end, { nargs = 0 })
    end,
  },
  {
    "HiPhish/rainbow-delimiters.nvim",
    enabled = false,
    -- dir = "~/Git/github/rainbow-delimiters.nvim",
    -- tag = "v0.9.1",
    submodules = false,
    ---@type rainbow_delimiters.config
    opts = {
      strategy = {
        [""] = "rainbow-delimiters.strategy.global",
      },
      query = {
        [""] = "rainbow-delimiters",
      },
      priority = {
        [""] = 110,
        lua = 210,
      },
      log = {
        level = vim.log.levels.TRACE,
      },
      highlight = require("colors").rainbow_highlight,
    },
    config = function(_, opts)
      require("rainbow-delimiters.setup").setup(opts)
    end,
  },
  {
    "saghen/blink.pairs",
    -- version = "*", -- (recommended) only required with prebuilt binaries
    version = false,
    enabled = true,
    -- download prebuilt binaries from github releases
    dependencies = not vim.g.has_nightly_rust and "saghen/blink.download",
    -- OR build from source, requires nightly:
    -- https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    build = vim.g.has_ocargo and "fish --command 'ocargo --nightly build --release'"
      or (vim.g.has_nightly_rust and "cargo +nightly build --release"),
    -- If you use nix, you can build from source using latest nightly rust with:
    -- build = 'nix run .#build-plugin',

    --- @module 'blink.pairs'
    --- @type blink.pairs.Config
    opts = {
      mappings = {
        -- you can call require("blink.pairs.mappings").enable()
        -- and require("blink.pairs.mappings").disable()
        -- to enable/disable mappings at runtime
        enabled = false,
        cmdline = false,
        -- or disable with `vim.g.pairs = false` (global) and `vim.b.pairs = false` (per-buffer)
        -- and/or with `vim.g.blink_pairs = false` and `vim.b.blink_pairs = false`
        disabled_filetypes = {},
        -- see the defaults:
        -- https://github.com/Saghen/blink.pairs/blob/main/lua/blink/pairs/config/mappings.lua#L14
        pairs = {},
      },
      highlights = {
        enabled = true,
        -- requires require('vim._extui').enable({}), otherwise has no effect
        cmdline = true,
        -- groups = {
        --   "BlinkPairsOrange",
        --   "BlinkPairsPurple",
        --   "BlinkPairsBlue",
        -- },
        groups = require("colors").rainbow_highlight,
        unmatched_group = "BlinkPairsUnmatched",
        -- {

        -- highlights matching pairs under the cursor
        matchparen = {
          enabled = true,
          -- known issue where typing won't update matchparen highlight, disabled by default
          cmdline = false,
          -- also include pairs not on top of the cursor, but surrounding the cursor
          include_surrounding = true,
          group = "BlinkPairsMatchParen",
          priority = 250,
        },
      },
      debug = false,
    },
  },
  {
    "saghen/blink.indent",
    enabled = false,
    --- @module 'blink.indent'
    --- @type blink.indent.Config
    opts = {
      -- mappings = {
      --   border = "none",
      --   object_scope = "",
      --   object_scope_with_border = "",
      --   goto_top = "",
      --   goto_bottom = "",
      -- },
      mappings = {
        -- which lines around the scope are included for 'ai': 'top', 'bottom', 'both', or 'none'
        border = "both",
        -- set to '' to disable
        -- textobjects (e.g. `y2ii` to yank current and outer scope)
        object_scope = "ii",
        object_scope_with_border = "ai",
        -- motions
        goto_top = "[i",
        goto_bottom = "]i",
      },
      static = {
        enabled = true,
        -- char = "▎",
        char = vim.g.indent_char,
        priority = 1,
        -- specify multiple highlights here for rainbow-style indent guides
        -- highlights = { 'BlinkIndentRed', 'BlinkIndentOrange', 'BlinkIndentYellow', 'BlinkIndentGreen', 'BlinkIndentViolet', 'BlinkIndentCyan' },
        highlights = { "BlinkIndent" },
      },
      scope = {
        enabled = true,
        -- char = "▎",
        char = vim.g.indent_char,
        priority = 10,
        -- highlights = { "BlinkIndentOrange", "BlinkIndentViolet", "BlinkIndentBlue" },
        highlights = require("colors").rainbow_highlight,
        -- enable to show underlines on the line above the current scope
        underline = {
          enabled = true,
          priority = 1,
          highlights = {
            "BlinkIndentYellowUnderline",
            "BlinkIndentVioletUnderline",
            "BlinkIndentBlueUnderline",
            "BlinkIndentOrangeUnderline",
            "BlinkIndentRedUnderline",
            "BlinkIndentCyanUnderline",
            "BlinkIndentGreenUnderline",
          },
        },
      },
    },
    --- @param opts blink.indent.Config
    config = function(_, opts)
      require("blink.indent").setup(opts)

      local scope = require("blink.indent.scope")
      local config = require("blink.indent.config")
      local utils = require("blink.indent.utils")
      ---@diagnostic disable-next-line: undefined-field
      local priority = opts.scope.underline.priority
      -- local orig_draw_underline = blink_indent.draw_underline

      -- monkey patch underline draw function to use lower priority
      ---@diagnostic disable-next-line: duplicate-set-field
      scope.draw_underline = function(bufnr, ns, indent_levels, scope_range)
        local indent_level = scope_range.indent_level
        local previous_line_indent_level = indent_levels[scope_range.start_line - 1]

        if previous_line_indent_level == nil or previous_line_indent_level >= indent_level then
          return
        end
        local line = vim.api.nvim_buf_get_lines(bufnr, scope_range.start_line - 2, scope_range.start_line - 1, false)[1]
        local whitespace_chars = line:match("^%s*")
        vim.hl.range(
          bufnr,
          ns,
          utils.get_rainbow_hl(previous_line_indent_level, config.scope.underline.highlights),
          { scope_range.start_line - 2, #whitespace_chars },
          { scope_range.start_line - 2, -1 },
          { priority = priority }
        )
      end
    end,
  },
  {
    "nvim-mini/mini.icons",
    lazy = true,
    opts = {
      -- default = {},
      -- directory = {},
      -- extension = {
      --   ttl = { glyph = "󰳗" },
      -- },
      file = {
        -- [".keep"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
        -- ["devcontainer.json"] = { glyph = "", hl = "MiniIconsAzure" },
        [".bash_aliases"] = { glyph = "󰒓", hl = "MiniIconsGreen" },
        [".bash_env"] = { glyph = "󰒓", hl = "MiniIconsGreen" },
        [".bash_make"] = { glyph = "󰒓", hl = "MiniIconsGreen" },
        [".bash_prompt"] = { glyph = "󰒓", hl = "MiniIconsGreen" },
        [".bash_logout"] = { glyph = "󰒓", hl = "MiniIconsGreen" },
      },
      -- stylua: ignore start
      filetype = {
        -- dotenv = { glyph = "", hl = "MiniIconsYellow" },
        ["javascript.jsx"] = { glyph = "", hl = "MiniIconsYellow" },
        javascriptreact = { glyph = "", hl = "MiniIconsBlue" },
        ["json.openapi"] = { glyph = "", hl = "MiniIconsGreen" },
        ["markdown.mdx"] = { glyph = "󰍔", hl = "MiniIconsGrey" },
        ["typescript.tsx"] = { glyph = "", hl = "MiniIconsBlue" },
        ["yaml.gitlab"] = { glyph = "", hl = "MiniIconsPurple" },
        ["yaml.helm-values"] = { glyph = "", hl = "MiniIconsPurple" },
        ["yaml.openapi"] = { glyph = "", hl = "MiniIconsGreen" },
        ["yaml.chezmoitmpl"] = { glyph = "", hl = "MiniIconsGreen" },

        ["atlas-*"] = { glyph = "󰫮", hl = "MiniIconsAzure" },
        agda = { glyph = "󱗆", hl = "MiniIconsGrey" },
        aiken = { glyph = "󰞍", hl = "MiniIconsPurple" },
        alloy = { glyph = "󱠦", hl = "MiniIconsGrey" },
        antlers = { glyph = "󰬀", hl = "MiniIconsGrey" },
        apex = { glyph = "", hl = "MiniIconsBlue" },
        apexcode = { glyph = "", hl = "MiniIconsBlue" },
        ato = { glyph = "", hl = "MiniIconsOrange" },
        ballerina = {glyph="", hl="MiniIconsCyan" },
        bazelrc = { glyph = "", hl = "MiniIconsGreen" },
        brs = {glyph="󰬙", color="MiniIconsPurple" },
        brioche = {glyph="", hl="MiniIconsYellow" },
        bsl = {glyph="", hl="MiniIconsGrey"},
        bean              = { glyph = '󰫯', hl = 'MiniIconsAzure'  },
        cython = { glyph = "󰫽", hl = "MiniIconsYellow" },
        os = {glyph="", hl="MiniIconsGrey" },
        dfy = { glyph = "󰫱", hl = "MiniIconsYellow" },
        fish = { glyph = "󰈺" },
        latex = { glyph = "", hl = "MiniIconsGreen" },
        marko = { glyph = "󰫺", hl = "MiniIconsOrange" },
        nextflow = { glyph = "", hl = "MiniIconsGreen" },
        opencl = { glyph = "" },
        pdll = { glyph = "", hl = "MiniIconsGreen" },
        postcss = { glyph = "", hl = "MiniIconsOrange" },
        profile = { glyph = "󱌼", hl = "MiniIconsGreen" },
        qmljs = { glyph = "󰫾", hl = "MiniIconsAzure" },
        sty = { glyph = "", hl = "MiniIconsGreen" },
        ttl = { glyph = "󰳗", hl = "MiniIconsGreen" },
        vlang = { glyph = "", hl = "MiniIconsBlue" },
        yql                    = { glyph = "󰬆", hl = "MiniIconsGreen"  },
        sh                     = { glyph = "", hl = "MiniIconsGrey"   },
        gduid = { glyph = '', hl = 'MiniIconsGrey' },
        glb = { glyph = '', hl = 'MiniIconsGrey' },
      },
      -- stylua ignore end
      -- lsp = {},
      -- os = {},
    },
    -- init = function()
    --   package.preload["nvim-web-devicons"] = function()
    --     require("mini.icons").mock_nvim_web_devicons()
    --     return package.loaded["nvim-web-devicons"]
    --   end
    -- end,
  },
  {
    "lewis6991/hover.nvim",
    lazy = true,
    keys = {
      -- { "<leader>u<C-i>", false, desc = "Toggle hover.nvim on CursorHold" },
    },
    opts = {
      --- List of modules names to load as providers.
      --- @type (string|Hover.Config.Provider)[]
      providers = {
        -- "hover.providers.diagnostic",
        -- "hover.providers.lsp",
        -- "hover.providers.dap",
        -- "hover.providers.man",
        -- "hover.providers.dictionary",
        -- Optional, disabled by default:
        -- 'hover.providers.gh',
        -- 'hover.providers.gh_user',
        -- 'hover.providers.jira',
        -- "hover.providers.fold_preview",
        "hover.providers.highlight",
      },
      preview_opts = {
        border = "rounded",
      },
      -- Whether the contents of a currently open hover window should be moved
      -- to a :h preview-window when pressing the hover keymap.
      preview_window = false,
      title = true,
      mouse_providers = {
        "hover.providers.lsp",
      },
      mouse_delay = 1000,
    },
  },
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    dependencies = {
      {
        "neovim/nvim-lspconfig",
        opts = { diagnostics = { signs = false, virtual_text = false } },
      },
    },
    enabled = false,
    event = "VeryLazy",
    priority = 1000,
    opts = {
      options = {
        add_messages = {
          messages = true, -- Show full diagnostic messages
          display_count = false, -- Show diagnostic count instead of messages when cursor not on line
          use_max_severity = false, -- When counting, only show the most severe diagnostic
          show_multiple_glyphs = true, -- Show multiple icons for multiple diagnostics of same severity
        },
        multilines = {
          enabled = true,
          always_show = true,
        },
        show_source = {
          enabled = true,
          if_many = true,
        },
        use_icons_from_diagnostic = true,
        set_arrow_to_diag_color = false,
        show_all_diags_on_cursorline = true,
      },
    },
    config = function(_, opts)
      local highlights = require("tiny-inline-diagnostic.highlights")
      local diagnostic_signs = {
        [vim.diagnostic.severity.ERROR] = LazyVim.config.icons.diagnostics.Error,
        [vim.diagnostic.severity.WARN] = LazyVim.config.icons.diagnostics.Warn,
        [vim.diagnostic.severity.HINT] = LazyVim.config.icons.diagnostics.Hint,
        [vim.diagnostic.severity.INFO] = LazyVim.config.icons.diagnostics.Info,
      }
      highlights.get_diagnostic_icon = function(severity)
        return diagnostic_signs[severity]
      end
      require("tiny-inline-diagnostic").setup(opts)

      -- vim.notify(vim.fn.sign_getdefined("DiagnosticSignError"))
      vim.diagnostic.config({ virtual_text = false }) -- Disable Neovim's default virtual text diagnostics
    end,
  },
  -- {
  --   "dmtrKovalenko/fff.nvim",
  --   build = function()
  --     -- this will download prebuild binary or try to use existing rustup toolchain to build from source
  --     -- (if you are using lazy you can use gb for rebuilding a plugin if needed)
  --     require("fff.download").download_or_build_binary()
  --   end,
  --   -- if you are using nixos
  --   -- build = "nix run .#release",
  --   opts = { -- (optional)
  --     debug = {
  --       enabled = true, -- we expect your collaboration at least during the beta
  --       show_scores = true, -- to help us optimize the scoring system, feel free to share your scores!
  --     },
  --   },
  --   -- No need to lazy-load with lazy.nvim.
  --   -- This plugin initializes itself lazily.
  --   lazy = false,
  --   keys = {
  --     {
  --       "<leader><leader>", -- try it if you didn't it is a banger keybinding for a picker
  --       function()
  --         require("fff").find_files()
  --       end,
  --       desc = "FFFind files",
  --     },
  --   },
  -- },
}
