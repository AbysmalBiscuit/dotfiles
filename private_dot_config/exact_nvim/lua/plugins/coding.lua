-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

-- Variable to track if completion pop-up should be shown
-- vim.g.show_completions = true
--stylua: disable
-- patterns = {},

---@alias HideCmpMenu fun(cmp: blink.cmp.API): boolean

---Builds the function that hides the Cmp menu
---@return function
local function get_hide_cmp_menu()
  ---@param cmp blink.cmp.API
  ---@return boolean hid_something True when the menu was hidden
  local function hide_cmp_menu(cmp)
    return false
  end

  -- local blink_windows_menu = require("blink.cmp.completion.windows.menu")

  if vim.g.has_tabnine then
    function hide_cmp_menu(cmp)
      local hid_something = false
      if require("blink.cmp.completion.windows.menu").win:is_open() then
        cmp.hide()
        hid_something = true
      end
      if vim.g.tabnine_enabled and require("tabnine.keymaps").has_suggestion() then
        require("tabnine.keymaps").dismiss_suggestion()
        hid_something = true
      end
      return hid_something
    end
  else
    function hide_cmp_menu(cmp)
      if require("blink.cmp.completion.windows.menu").win:is_open() then
        cmp.hide()
        return true
      end
      return false
    end
  end
  return hide_cmp_menu
end

---@return fun(cmp: blink.cmp.API): boolean false The returned function always returns false
local function get_hide_cmp_menu_and_do_next()
  if vim.g.has_tabnine then
    return function(cmp)
      if require("blink.cmp.completion.windows.menu").win:is_open() then
        cmp.hide()
      end
      if vim.g.tabnine_enabled and require("tabnine.keymaps").has_suggestion() then
        require("tabnine.keymaps").dismiss_suggestion()
      end
      return false
    end
  else
    return function(cmp)
      if require("blink.cmp.completion.windows.menu").win:is_open() then
        cmp.hide()
      end
      return false
    end
  end
end

---@param direction "up" | "down" Direction to scroll
---@param opts blink.cmp.CompletionListSelectOpts Opts passed to scroll function
---@return fun(cmp: blink.cmp.API): boolean? function that will scroll in the desired direction with the given options
local function get_scroll_function(direction, opts)
  if direction == "up" then
    return function(cmp)
      return cmp.select_prev(opts)
    end
  end

  return function(cmp)
    return cmp.select_next(opts)
  end
end

---@type LazyPluginSpec[]
return {
  {
    "saghen/blink.cmp",
    build = vim.g.is_macos
        and "fish --command 'RUSTFLAGS=\"-C link-arg=-L/usr/local/lib -C link-arg=-lluajit\" ocargo --nightly --no-mold build --release'"
      or vim.g.has_ocargo and "fish --command 'ocargo --nightly --lto --dylib build --release'"
      or (vim.g.has_nightly_rust and "cargo +nightly build --release"),
    dependencies = {
      -- "codota/tabnine-nvim"
      { "mikavilpas/blink-ripgrep.nvim", version = "*" },
      { "moyiz/blink-emoji.nvim" },
      { "bydlw98/blink-cmp-env" },
    },
    keys = {
      {
        "<C-S-space>",
        function()
          local new_state = ""
          if vim.g.blink_cmp then
            new_state = "disabled"
            require("blink.cmp").hide()
          else
            new_state = "enabled"
          end
          Snacks.notify.info("Toggle blink: " .. new_state)
          vim.g.blink_cmp = not vim.g.blink_cmp
        end,
        mode = { "n", "i" },
        desc = "Toggle completions",
      },
    },
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      enabled = function()
        return vim.g.blink_cmp ~= false
      end,

      -- Controls how the completion items are selected
      completion = {
        list = {
          selection = { preselect = false, auto_insert = false },
        },
        keyword = {
          range = "prefix",
        },
        accept = {
          dot_repeat = true,
          create_undo_point = true,
          auto_brackets = {
            enabled = false,
          },
        },
        documentation = {
          window = { border = "rounded" },
        },
        ghost_text = {
          enabled = true,
        },
        menu = {
          border = "none",
          draw = {
            columns = { { "item_idx" }, { "kind_icon" }, { "label", "label_description", gap = 1 } },
            components = {
              item_idx = {
                text = function(ctx)
                  return ctx.idx == 10 and "0" or ctx.idx >= 10 and " " or tostring(ctx.idx)
                end,
                -- highlight = "BlinkCmpItemIdx", -- optional, only if you want to change its color
              },
            },
          },
        },
        trigger = {
          show_on_keyword = true,
          show_on_trigger_character = true,
          -- show_on_blocked_trigger_characters = {},
          show_on_blocked_trigger_characters = function(ctx)
            if vim.bo.filetype == "rust" then
              return {}
            end
            -- if vim.bo.filetype == "markdown" then
            --   return { " ", "\n", "\t", ".", "/", "(", "[" }
            -- end
            -- default setting: show_on_blocked_trigger_characters = { " ", "\n", "\t" }
            return { " ", "\n", "\t" }
          end,
        },
      },

      sources = {
        default = {
          "buffer",
          "lsp",
          "path",
          "snippets",
          "ripgrep",
          "emoji",
          "env",
          -- "avante",
          -- "ecolog",
          -- "obsidian",
          -- "obsidian_new",
          -- "obsidian_tags",
        },
        providers = {
          lsp = {
            async = true,
            score_offset = 4,
            override = {
              get_trigger_characters = function(self)
                local trigger_characters = self:get_trigger_characters()
                vim.list_extend(trigger_characters, { "\r", "\n", "\t", " " })
                return trigger_characters
              end,
            },
          },
          snippets = {
            name = "snippets",
            async = true,
            score_offset = 3,
            ---@type blink.cmp.SnippetsConfig
            opts = {
              friendly_snippets = true,
              -- Base snippet files are auto loaded for each language
              extended_filetypes = {
                astro = { "typescript", "tsdoc", "react-ts" },
                bash = { "shell", "shelldoc" },
                c = { "cdoc" },
                gitcommit = {},
                javascript = { "jsdoc" },
                latex = { "latex-snippets", "vscode-latex-snippets" },
                lua = { "lua", "luadoc" },
                python = { "pydoc", "unittest", "comprehension" },
                rust = { "rustdoc" },
                shell = { "shelldoc" },
                typescript = { "react-ts", "tsdoc" },
                zsh = { "shell", "shelldoc" },
              },
              module = "blink.cmp.sources.snippets",
            },
          },
          path = {
            async = true,
            score_offset = 6,
          },
          buffer = {
            async = true,
            score_offset = 0,
          },
          ripgrep = {
            module = "blink-ripgrep",
            name = "Ripgrep",
            score_offset = -2,
            async = true,
            ---@module "blink-ripgrep"
            ---@type blink-ripgrep.Options
            opts = {
              prefix_min_len = 3,
              -- project_root_marker = { ".git", "pyproject.toml", "Vault.md" },
              backend = {
                use = "gitgrep-or-ripgrep",
                ripgrep = {
                  context_size = 5,
                  max_filesize = "1M",
                },
              },
              debug = false,
            },
          },
          emoji = {
            module = "blink-emoji",
            name = "Emoji",
            score_offset = 15, -- Tune by preference
            async = true,

            transform_items = function(ctx, items)
              for _, item in ipairs(items) do
                item.kind_icon = "󰞅"
                item.kind_name = "Emoji"
              end
              return items
            end,
            opts = {
              insert = true, -- Insert emoji (default) or complete its name
              ---@type string|table|fun():table
              trigger = function()
                return { ":" }
              end,
            },
            should_show_items = function()
              return vim.bo.filetype == "gitcommit" or vim.bo.filetype == "markdown"
            end,
          },
          env = {
            name = "Env",
            module = "blink-cmp-env",
            async = true,
            ---@type blink-cmp-env.Options
            opts = {
              item_kind = require("blink.cmp.types").CompletionItemKind.Variable,
              show_braces = false,
              show_documentation_window = true,
            },
          },
          -- avante = {
          --   module = "blink-cmp-avante",
          --   name = "Avante",
          -- },
          -- ecolog = {
          --   name = "ecolog",
          --   module = "ecolog.integrations.cmp.blink_cmp",
          --   async = true,
          -- },
          -- obsidian_new = {
          --   name = "obsidian_new",
          --   module = "blink.compat.source",
          -- },
          -- obsidian_tags = {
          --   name = "obsidian_tags",
          --   module = "blink.compat.source",
          -- },
        },
      },
    },
    ---@param opts blink.cmp.Config | { sources: { compat: string[] } }
    config = function(_, opts)
      if opts.snippets and opts.snippets.preset == "default" then
        opts.snippets.expand = LazyVim.cmp.expand
      end
      -- vim.api.nvim__buf_debug_extmarks(buffer, keys, dot)

      -- Unset custom prop to pass blink.cmp validation
      opts.sources.compat = nil

      -- Override all keymaps set by Lazy
      opts.keymap = {
        -- preset = "enter",
        preset = "none",
        ["<C-space>"] = {
          ---@param cmp blink.cmp.API
          function(cmp)
            cmp.show()
          end,
          "show_documentation",
          "hide_documentation",
        },

        ["<C-e>"] = { get_hide_cmp_menu(), "fallback" },
        -- ["<CR>"] = { "accept", "fallback" },
        ["<CR>"] = { "fallback" },
        ["<C-n>"] = { "snippet_forward", "fallback" },
        ["<C-S-n>"] = { "snippet_backward", "fallback" },
        ["<Tab>"] = {
          "select_and_accept",
          LazyVim.cmp.map({ "snippet_forward", "ai_nes", "ai_accept" }),
          -- "snippet_forward",
          "fallback",
        },
        ["<S-Tab>"] = {
          "select_prev",
          "snippet_backward",
          "fallback",
        },
        ["<PageDown>"] = {
          get_scroll_function("down", {
            count = 5,
            auto_insert = opts.completion.list.selection.auto_insert or false,
            on_ghost_text = opts.completion.ghost_text.enabled or false,
          }),
          "fallback",
        },
        ["<PageUp>"] = {
          get_scroll_function("up", {
            count = 5,
            auto_insert = opts.completion.list.selection.auto_insert or false,
            on_ghost_text = opts.completion.ghost_text.enabled or false,
          }),
          "fallback",
        },
        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<Left>"] = { get_hide_cmp_menu_and_do_next(), "fallback" },
        ["<Right>"] = { get_hide_cmp_menu_and_do_next(), "fallback" },
        ["<C-b>"] = {},
        ["<C-f>"] = {
          "select_and_accept",
          "fallback",
        },
        ["<C-0>"] = {
          function(cmp)
            cmp.accept({ index = 0 })
          end,
          "fallback",
        },
        ["<C-p>"] = { "scroll_documentation_up", "fallback" },
        ["<C-t>"] = { "scroll_documentation_down", "fallback" },
      }

      for i = 1, 9 do
        opts.keymap[string.format("<C-%s>", i)] = {
          function(cmp)
            cmp.accept({ index = i })
          end,
          "fallback",
        }
      end

      opts = vim.tbl_deep_extend("force", opts, {
        cmdline = {
          enabled = true,
          keymap = {
            preset = "none",
            ["<C-f>"] = { "select_and_accept", "fallback" },
            ["<Up>"] = { "select_prev", "fallback" },
            ["<Down>"] = { "select_next", "fallback" },
            ["<Left>"] = { get_hide_cmp_menu_and_do_next(), "fallback" },
            ["<Right>"] = { get_hide_cmp_menu_and_do_next(), "fallback" },
            ["<PageDown>"] = {
              get_scroll_function("down", {
                count = 5,
                auto_insert = opts.completion.list.selection.auto_insert or false,
                on_ghost_text = opts.completion.ghost_text.enabled or false,
              }),
              "fallback",
            },
            ["<PageUp>"] = {
              get_scroll_function("up", {
                count = 5,
                auto_insert = opts.completion.list.selection.auto_insert or false,
                on_ghost_text = opts.completion.ghost_text.enabled or false,
              }),
              "fallback",
            },
          },
          completion = {
            list = { selection = { preselect = false } },
            menu = {
              auto_show = function(ctx)
                return vim.fn.getcmdtype() == ":"
              end,
            },
            ghost_text = {
              enabled = true,
            },
          },
        },
      })

      -- create user commands to toggle blink ripgrep
      vim.api.nvim_create_user_command("ToggleBlinkRipgrep", function(_, _, _)
        local blink_ripgrep = require("blink-ripgrep")
        if blink_ripgrep.config.mode == "on" then
          blink_ripgrep.config.mode = "off"
        else
          blink_ripgrep.config.mode = "on"
        end
        vim.notify("blink-ripgrep set to " .. blink_ripgrep.config.mode)
      end, {})

      -- update lsp transform items to remove ellipsis
      ---@type fun(ctx: blink.cmp.Context, items: blink.cmp.CompletionItem[]): blink.cmp.CompletionItem[]
      local transform_items = opts.sources.providers.lsp.transform_items

      if transform_items then
        ---@param ctx blink.cmp.Context
        ---@param items blink.cmp.CompletionItem[]
        opts.sources.providers.lsp.transform_items = function(ctx, items)
          items = transform_items(ctx, items)
          for _, item in ipairs(items) do
            item.label = string.gsub(item.label, "…", "...")
          end
          return items
        end
      else
        ---@param ctx blink.cmp.Context
        ---@param items blink.cmp.CompletionItem[]
        opts.sources.providers.lsp.transform_items = function(ctx, items)
          for _, item in ipairs(items) do
            item.label = string.gsub(item.label, "…", "...")
          end
          return items
        end
      end

      -- check if we need to override symbol kinds
      for _, provider in pairs(opts.sources.providers or {}) do
        ---@cast provider blink.cmp.SourceProviderConfig|{kind?:string}
        if provider.kind then
          local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
          local kind_idx = #CompletionItemKind + 1

          CompletionItemKind[kind_idx] = provider.kind
          ---@diagnostic disable-next-line: no-unknown
          CompletionItemKind[provider.kind] = kind_idx

          ---@type fun(ctx: blink.cmp.Context, items: blink.cmp.CompletionItem[]): blink.cmp.CompletionItem[]
          transform_items = provider.transform_items

          if transform_items then
            ---@param ctx blink.cmp.Context
            ---@param items blink.cmp.CompletionItem[]
            provider.transform_items = function(ctx, items)
              items = transform_items(ctx, items)
              for _, item in ipairs(items) do
                item.kind = kind_idx or item.kind
                item.kind_icon = LazyVim.config.icons.kinds[item.kind_name] or item.kind_icon or nil
              end
              return items
            end
          else
            ---@param ctx blink.cmp.Context
            ---@param items blink.cmp.CompletionItem[]
            provider.transform_items = function(ctx, items)
              for _, item in ipairs(items) do
                item.kind = kind_idx or item.kind
                item.kind_icon = LazyVim.config.icons.kinds[item.kind_name] or item.kind_icon or nil
              end
              return items
            end
          end

          -- Unset custom prop to pass blink.cmp validation
          provider.kind = nil
        end
      end

      require("blink.cmp").setup(opts)
    end,
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    ---@class nvim-autopairs
    opts = {
      map_bs = true,
      fast_wrap = {
        map = "<C-e>",
        -- end_key = "<End>",
        -- before_key = "<Left>",
        -- after_key = "<Right>",
        highlight = "FlashLabel",
        highlight_grey = "FlashBackdrop",
      },
    },
    config = function(_, opts)
      local npairs = require("nvim-autopairs")
      npairs.setup(opts)

      local Rule = require("nvim-autopairs.rule")
      local cond = require("nvim-autopairs.conds")
      local ts_conds = require("nvim-autopairs.ts-conds")

      for _, punct in pairs({ ",", ";" }) do
        npairs.add_rules({
          Rule("", punct)
            :with_move(function(o)
              return o.char == punct
            end)
            :with_pair(function()
              return false
            end)
            :with_del(function()
              return false
            end)
            :with_cr(function()
              return false
            end)
            :use_key(punct),
        })
      end
      Rule("%(.*%)%s*%=>$", " {  }", { "typescript", "typescriptreact", "javascript" })
        :use_regex(true)
        :set_end_pair_length(2)

      npairs.add_rule(Rule("<", ">", {
        -- if you use nvim-ts-autotag, you may want to exclude these filetypes from this rule
        -- so that it doesn't conflict with nvim-ts-autotag
        -- "-html",
        -- "-javascriptreact",
        -- "-typescriptreact",
      }):with_pair(
        -- regex will make it so that it will auto-pair on
        -- `a<` but not `a <`
        -- The `:?:?` part makes it also
        -- work on Rust generics like `some_func::<T>()`
        cond.before_regex("%a+:?:?$", 3)
      ):with_move(function(opts)
        return opts.char == ">"
      end))

      npairs.add_rules({
        Rule("{", "},", "lua"):with_pair(ts_conds.is_ts_node({ "table_constructor" })),
        Rule("'", "',", "lua"):with_pair(ts_conds.is_ts_node({ "table_constructor" })),
        Rule('"', '",', "lua"):with_pair(ts_conds.is_ts_node({ "table_constructor" })),
      })
    end,
  },
  {
    "nvim-mini/mini.surround",
    opts = {
      n_lines = 500,
    },
  },
  -- {
  --   "nvim-mini/mini.ai",
  --   opts = function()
  --     local ai = require("mini.ai")
  --     return {
  --       n_lines = 500,
  --       custom_textobjects = {
  --         o = ai.gen_spec.treesitter({ -- code block
  --           a = { "@block.outer", "@conditional.outer", "@loop.outer" },
  --           i = { "@block.inner", "@conditional.inner", "@loop.inner" },
  --         }),
  --         f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }), -- function
  --         c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }), -- class
  --         t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" }, -- tags
  --         d = { "%f[%d]%d+" }, -- digits
  --         e = { -- Word with case
  --           { "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
  --           "^().*()$",
  --         },
  --         g = LazyVim.mini.ai_buffer, -- buffer
  --         u = ai.gen_spec.function_call(), -- u for "Usage"
  --         U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }), -- without dot in function name
  --       },
  --     }
  --   end,
  -- },
  -- {
  --   "L3MON4D3/LuaSnip",
  --   dependencies = {
  --     {
  --       "rafamadriz/friendly-snippets",
  --       --     config = function(_, opts)
  --       --       -- vim.tbl_map(function(type)
  --       --       --   require("luasnip.loaders.from_" .. type).lazy_load()
  --       --       -- end, {
  --       --       --   --"vscode",
  --       --       --   "snipmate",
  --       --       --   "lua",
  --       --       -- })
  --       --       -- require("luasnip.loaders.from_vscode").lazy_load()
  --       --       require("luasnip.loaders.from_vscode").lazy_load({
  --       --         paths = { "~/.config/nvim/snippets" }, -- Path to your custom snippets
  --       --       })
  --       --     end,
  --     },
  --   },
  --   config = function(_, opts)
  --     local ls = require("luasnip")
  --     if opts then
  --       ls.config.setup(opts)
  --     end
  --     ls.filetype_extend("c", { "cdoc" })
  --     ls.filetype_extend("lua", { "lua", "luadoc" })
  --     ls.filetype_extend("latex", { "latex-snippets", "vscode-latex-snippets" })
  --     ls.filetype_extend("javascript", { "javascript", "jsdoc" })
  --     ls.filetype_extend("typescript", { "react-ts", "tsdoc" })
  --     ls.filetype_extend("python", { "python", "debug", "pydoc", "unittest", "comprehension.json" })
  --     ls.filetype_extend("rust", { "rust", "rustdoc" })
  --     ls.filetype_extend("shell", { "shell", "shelldoc" })
  --     ls.filetype_extend("editorconfig", { "editorconfig" })
  --     ls.filetype_extend("markdown", { "markdown" })
  --   end,
  -- },
  {
    "monaqa/dial.nvim",
    opts = function(_, opts)
      local augend = require("dial.augend")
      local new = require("dial.augend").constant.new
      opts.dials_by_ft = vim.tbl_extend("force", opts.dials_by_ft, {
        rust = "rust",
      })
      opts.groups.default = vim.tbl_extend("force", opts.groups.default, {
        augend.date.alias["%Y-%m-%d"],
      })
      opts.groups.python = vim.tbl_extend("force", opts.groups.python, {
        new({
          elements = { "list", "tuple" },
          word = true,
          cyclic = true,
        }),
        new({
          elements = { "int", "float" },
          word = true,
          cyclic = true,
        }),
      })
      opts.groups.rust = vim.tbl_extend("force", opts.groups.rust or {}, {
        new({
          elements = { "u8", "u16", "u32", "u62", "u128" },
          word = true,
          cyclic = true,
        }),
        new({
          elements = { "i8", "i16", "i32", "i62", "i128" },
          word = true,
          cyclic = true,
        }),
        new({
          elements = { "String", "&String", "str", "&str" },
          word = true,
          cyclic = true,
        }),
      })
      opts.groups.markdown = vim.tbl_extend("force", opts.groups.markdown or {}, {
        new({
          elements = { "[ ]", "[x]" },
          word = true,
          cyclic = true,
        }),
        new({
          -- stylua: ignore
          elements = {
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
            "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
          },
          word = true,
          cyclic = true,
        }),
      })
    end,
  },
  -- {
  --   "folke/which-key.nvim",
  --   event = "VeryLazy",
  --   opts = {
  --     triggers = {
  --       { "<auto>", mode = "" },
  --     },
  --   },
  --   keys = {},
  -- },
  {
    "AbysmalBiscuit/insert-inlay-hints.nvim",
    -- dir = "~/Git/lev/insert-inlay-hints.nvim",
    -- opts = { debug = true },
    keys = {
      {
        "<leader>ic",
        function()
          require("insert-inlay-hints").closest()
        end,
        desc = "Insert the colsest inline hint as code.",
      },
      {
        "<leader>il",
        function()
          require("insert-inlay-hints").line()
        end,
        desc = "Insert all inline hints on current line as code.",
      },
      {
        "<leader>i",
        function()
          require("insert-inlay-hints").visual()
        end,
        desc = "Insert all inlay hints in the current visual selection as code.",
        mode = { "v" },
      },
      {
        "<leader>ia",
        function()
          require("insert-inlay-hints").all()
        end,
        desc = "Insert all inlay hints in the current buffer as code.",
      },
    },
    ---@type insert-inlay-hints.Config
    opts = {
      -- debug = true,
      -- disabled_lsps = { "vtsls" },
    },
  },
  -- {
  --   "AckslD/muren.nvim",
  --   event = {
  --     { "BufNewFile", "BufAdd" },
  --   },
  --   cmd = "MurenToggle",
  --   keys = {
  --     {
  --       "<leader>se",
  --       function()
  --         require("muren.api").toggle_ui()
  --       end,
  --       desc = "Toggle Muren",
  --       mode = { "n", "i" },
  --     },
  --   },
  --   -- config = true,
  --   opts = {
  --     patterns_width = 60,
  --     patterns_height = 20,
  --     options_width = 40,
  --     preview_height = 24,
  --   },
  -- },
  --   {
  --     "ph1losof/ecolog.nvim",
  --     -- Optional: you can add some keybindings
  --     -- (I personally use lspsaga so check out lspsaga integration or lsp integration for a smoother experience without separate keybindings)
  --     keys = {
  --       -- { "<leader>ge", "<cmd>EcologGoto<cr>", desc = "Go to env file" },
  --       -- { "<leader>ep", "<cmd>EcologPeek<cr>", desc = "Ecolog peek variable" },
  --       -- { "<leader>es", "<cmd>EcologSelect<cr>", desc = "Switch env file" },
  --     },
  --     -- Lazy loading is done internally
  --     lazy = false,
  --     opts = {
  --       integrations = {
  --         -- WARNING: for both cmp integrations see readme section below
  --         nvim_cmp = false, -- If you dont plan to use nvim_cmp set to false, enabled by default
  --         -- If you are planning to use blink cmp uncomment this line
  --         blink_cmp = true,
  --       },
  --       -- Enables shelter mode for sensitive values
  --       shelter = {
  --         configuration = {
  --           -- Partial mode configuration:
  --           -- false: completely mask values (default)
  --           -- true: use default partial masking settings
  --           -- table: customize partial masking
  --           -- partial_mode = false,
  --           -- or with custom settings:
  --           partial_mode = {
  --             show_start = 3, -- Show first 3 characters
  --             show_end = 3, -- Show last 3 characters
  --             min_mask = 3, -- Minimum masked characters
  --           },
  --           mask_char = "*", -- Character used for masking
  --           mask_length = nil, -- Optional: fixed length for masked portion (defaults to value length)
  --           skip_comments = false, -- Skip masking comment lines in environment files (default: false)
  --         },
  --         modules = {
  --           cmp = true, -- Enabled to mask values in completion
  --           peek = false, -- Enable to mask values in peek view
  --           files = true, -- Enabled to mask values in file buffers
  --           telescope = false, -- Enable to mask values in telescope integration
  --           telescope_previewer = false, -- Enable to mask values in telescope preview buffers
  --           fzf = false, -- Enable to mask values in fzf picker
  --           fzf_previewer = false, -- Enable to mask values in fzf preview buffers
  --           snacks_previewer = false, -- Enable to mask values in snacks previewer
  --           snacks = false, -- Enable to mask values in snacks picker
  --         },
  --       },
  --       -- true by default, enables built-in types (database_url, url, etc.)
  --       types = true,
  --       path = vim.fn.getcwd(), -- Path to search for .env files
  --       preferred_environment = "development", -- Optional: prioritize specific env files
  --       -- Controls how environment variables are extracted from code and how cmp works
  --       provider_patterns = true, -- true by default, when false will not check provider patterns
  --     },
  --   },
  {

    "gbprod/yanky.nvim",
    keys = {
      { "<leader>p", false },
      {
        "<leader>P",
        function()
          if LazyVim.pick.picker.name == "telescope" then
            require("telescope").extensions.yank_history.yank_history({})
          elseif LazyVim.pick.picker.name == "snacks" then
            Snacks.picker.yanky()
          else
            vim.cmd([[YankyRingHistory]])
          end
        end,
        mode = { "n", "x" },
        desc = "Open Yank History",
      },
    },
  },
  -- {
  --   "sQVe/sort.nvim",
  --   opts = {
  --     mappings = false,
  --   },
  -- },
  {
    "abecodes/tabout.nvim",
    enabled = false,
    lazy = false,
    opt = true, -- Set this to true if the plugin is optional
    event = "InsertCharPre", -- Set the event to 'InsertCharPre' for better compatibility
    priority = 1000,
    opts = {
      tabkey = "<C-n>", -- key to trigger tabout, set to an empty string to disable
      backwards_tabkey = "<C-S-n>", -- key to trigger backwards tabout, set to an empty string to disable
      act_as_tab = true, -- shift content if tab out is not possible
      act_as_shift_tab = false, -- reverse shift content if tab out is not possible (if your keyboard/terminal supports <S-Tab>)
      default_tab = "<C-t>", -- shift default action (only at the beginning of a line, otherwise <TAB> is used)
      default_shift_tab = "<C-d>", -- reverse shift default action,
      enable_backwards = true, -- well ...
      completion = false, -- if the tabkey is used in a completion pum
      tabouts = {
        { open = "'", close = "'" },
        { open = '"', close = '"' },
        { open = "`", close = "`" },
        { open = "(", close = ")" },
        { open = "[", close = "]" },
        { open = "{", close = "}" },
      },
      ignore_beginning = true, --[[ if the cursor is at the beginning of a filled element it will rather tab out than shift the content ]]
      exclude = {}, -- tabout will ignore these filetypes
    },
    dependencies = { -- These are optional
      "nvim-treesitter/nvim-treesitter",
      "saghen/blink.cmp",
    },
  },
}
