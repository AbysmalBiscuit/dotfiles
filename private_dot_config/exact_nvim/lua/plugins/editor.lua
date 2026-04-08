-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

-- local function toggle_harpoon_window(harpoon_files)
--   -- table for faster lookup
--   local harpoon_files_table = {}
--
--   -- Extract paths from harpoon_files
--   local finder = function(fzf_cb)
--     for i, item in ipairs(harpoon_files.items) do
--       harpoon_files_table[item.value] = i
--       fzf_cb(item.value)
--     end
--
--     fzf_cb()
--   end
--
--   -- Open fzf-lua picker
--   require("fzf-lua").fzf_exec(finder, {
--     prompt = "󱡅  ",
--     previewer = "builtin",
--     actions = {
--       ["default"] = require("fzf-lua.actions").file_edit,
--       ["ctrl-d"] = {
--         fn = function(selected, _)
--           for _, f in ipairs(selected) do
--             if harpoon_files_table[f] then
--               table.remove(harpoon_files.items, harpoon_files_table[f])
--             end
--           end
--         end,
--         reload = true,
--       },
--     },
--     -- Optional layout configurations
--     fzf_opts = {
--       ["--height"] = "40%",
--       ["--layout"] = "reverse",
--     },
--   })
-- end

---@type LazyPluginSpec[]
return {
  {
    "mikavilpas/yazi.nvim",
    -- event = "VeryLazy",
    enabled = true,
    lazy = false,
    keys = {
      -- 👇 in this section, choose your own keymappings!
      {
        "<leader>-",
        "<cmd>Yazi cwd<cr>",
        desc = "Open the file manager in nvim's working directory",
      },
      {
        "<leader>_",
        "<cmd>Yazi<cr>",
        desc = "Open yazi at the current file",
      },
      -- {
      --   "<leader>cw",
      --   "<cmd>Yazi cwd<cr>",
      --   desc = "Open the file manager in nvim's working directory",
      -- },
      {
        "<leader>/",
        "<cmd>Yazi toggle<cr>",
        desc = "Resume the last yazi session",
      },
    },
    ---@type YaziConfig
    opts = {
      -- if you want to open yazi instead of netrw, see below for more info
      open_for_directories = true,
      keymaps = {
        show_help = "<f1>",
        cycle_open_buffers = "<c-tab>",
      },
      open_multiple_tabs = true,
      change_neovim_cwd_on_close = false,
      integrations = {
        grep_in_selected_files = "snacks.picker",
        grep_in_directory = "snacks.picker",
      },
      -- future_features = {
      --   nvim_0_10_termopen_fallback = false,
      --
      --   -- Whether to use `ya emit reveal` to reveal files in the file manager.
      --   -- Requires yazi 0.4.0 or later (from 2024-12-08).
      --   ya_emit_reveal = true,
      --
      --   -- Use `ya emit open` as a more robust implementation for opening files
      --   -- in yazi. This can prevent conflicts with custom keymappings for the enter
      --   -- key. Requires yazi 0.4.0 or later (from 2024-12-08).
      --   ya_emit_open = true,
      -- },
    },
    -- config = function(_, opts)
    --   require("yazi").setup(opts)
    -- end,
    init = function()
      vim.g.loaded_netrwPlugin = 1
    end,
  },
  -- FZF changes
  {
    "ibhagwan/fzf-lua",
    enabled = false,
    opts = {
      fzf_bin = vim.env.SK_EXECUTABLE or nil,
      oldfiles = {
        -- In Telescope, when I used <leader>fr, it would load old buffers.
        -- fzf lua does the same, but by default buffers visited in the current
        -- session are not included. I use <leader>fr all the time to switch
        -- back to buffers I was just in. If you missed this from Telescope,
        -- give it a try.
        include_current_session = true,
      },
      previewers = {
        builtin = {
          -- fzf-lua is very fast, but it really struggled to preview a couple files
          -- in a repo. Those files were very big JavaScript files (1MB, minified, all on a single line).
          -- It turns out it was Treesitter having trouble parsing the files.
          -- With this change, the previewer will not add syntax highlighting to files larger than 100KB
          -- (Yes, I know you shouldn't have 100KB minified files in source control.)
          syntax_limit_b = 1024 * 100, -- 100KB
        },
      },
      ui_select = {
        winopts = {
          preview = { hidden = "nohidden" },
        },
      },
      file_ignore_patterns = {
        "node_modules/",
        "dist/",
        ".next/",
        ".git/",
        ".gitlab/",
        "build/",
        "target/",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        -- ".venv/",
        -- "venv/",
        ".mypy_cache/",
      },
    },
    keys = {
      { "<leader>s/", LazyVim.pick("live_grep"), desc = "Grep (Root Dir)" },
      { "<leader>/", false },
    },
  },
  {
    -- https://github.com/numToStr/Navigator.nvim
    -- "numToStr/Navigator.nvim",
    "craigmac/nvim-navigator",
    event = "VeryLazy",
    enabled = true,
    keys = {
      {
        "<C-Left>",
        function()
          require("Navigator").left()
        end,
        desc = "Navigate to left window or tmux pane.",
        mode = { "n", "t" },
      },
      {
        "<C-Down>",
        function()
          require("Navigator").down()
        end,
        desc = "Navigate to down window or tmux pane.",
        mode = { "n", "t" },
      },
      {
        "<C-Up>",
        function()
          require("Navigator").up()
        end,
        desc = "Navigate to up window or tmux pane.",
        mode = { "n", "t" },
      },
      {
        "<C-Right>",
        function()
          require("Navigator").right()
        end,
        desc = "Navigate to right window or tmux pane.",
        mode = { "n", "t" },
      },
    },
    -- keys = {
    --   {
    --     "<C-Left>",
    --     "<Cmd>NavigatorLeft<CR>",
    --     desc = "Navigate to left window or tmux pane.",
    --     mode = { "n", "t" },
    --   },
    --   {
    --     "<C-Down>",
    --     "<Cmd>NavigatorDown<CR>",
    --
    --     desc = "Navigate to down window or tmux pane.",
    --     mode = { "n", "t" },
    --   },
    --   {
    --     "<C-Up>",
    --     "<Cmd>NavigatorUp<CR>",
    --     desc = "Navigate to up window or tmux pane.",
    --     mode = { "n", "t" },
    --   },
    --   {
    --     "<C-Right>",
    --     "<Cmd>NavigatorRight<CR>",
    --     desc = "Navigate to right window or tmux pane.",
    --     mode = { "n", "t" },
    --   },
    -- },
    config = function()
      require("Navigator").setup({})
    end,
  },
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    keys = {
      {
        "<leader>h",
        function()
          local list = require("harpoon"):list()
          local picker_items = {}

          for i, item in ipairs(list.items) do
            table.insert(picker_items, {
              idx = i,
              -- Harpoon stores paths relative to the project root
              file = item.value,
              text = item.value,
            })
          end
          Snacks.picker.pick({
            title = "Harpoon",
            prompt = "󱡅  ",
            items = picker_items,
            -- finder = function(opts, ctx)
            --   return require("harpoon"):list()
            -- end,
            format = "file",
            confirm = function(picker, item)
              picker:close()
              list:select(item.idx)
            end,
            actions = {
              remove_harpooned_file = function(picker, item)
                table.remove(picker_items, item.idx)
                table.remove(list.items, item.idx)
                picker:refresh()
              end,
            },
            win = {
              input = {
                keys = {
                  ["<c-x>"] = { "remove_harpooned_file", mode = { "n", "i" } },
                },
              },
              list = {
                keys = {
                  ["dd"] = { "remove_harpooned_file", mode = "n" },
                },
              },
            },
          })
        end,
        desc = "Toggle harpoon window",
      },
    },
  },
  {
    "folke/trouble.nvim",
    keys = {
      {
        "[q",
        function()
          if require("trouble").is_open() then
            require("trouble").prev({ skip_groups = true, jump = true })
            vim.cmd("norm! zz")
          else
            local ok, err = pcall(vim.cmd.cprev)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "Previous Trouble/Quickfix Item",
      },
      {
        "]q",
        function()
          if require("trouble").is_open() then
            require("trouble").next({ skip_groups = true, jump = true })
            vim.cmd("norm! zz")
          else
            local ok, err = pcall(vim.cmd.cnext)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "Next Trouble/Quickfix Item",
      },
    },
    opts = {
      modes = {
        lsp = {
          win = {
            position = "left",
            relative = "win",
          },
        },
        symbols = {
          win = {
            position = "left",
            relative = "win",
          },
        },
      },
    },
  },
  -- {
  --   "jiaoshijie/undotree",
  --   dependencies = "nvim-lua/plenary.nvim",
  --   lazy = true,
  --   keys = { -- load the plugin only when using it's keybinding:
  --     { "<leader>r", "<cmd>lua require('undotree').toggle()<cr>", desc = "Toggle undotree" },
  --   },
  --   config = function()
  --     require("undotree").setup({
  --       float_diff = true, -- using float window previews diff, set this `true` will disable layout option
  --       layout = "left_bottom", -- "left_bottom", "left_left_bottom"
  --       position = "left", -- "right", "bottom"
  --       ignore_filetype = { "undotree", "undotreeDiff", "qf", "TelescopePrompt", "spectre_panel", "tsplayground" },
  --       window = {
  --         winblend = 10,
  --       },
  --       keymaps = {
  --         ["<Down>"] = "move_next",
  --         ["<Up>"] = "move_prev",
  --         ["gj"] = "move2parent",
  --         ["<S-Down>"] = "move_change_next",
  --         ["<S-Up>"] = "move_change_prev",
  --         ["<cr>"] = "action_enter",
  --         ["p"] = "enter_diffbuf",
  --         ["q"] = "quit",
  --       },
  --     })
  --   end,
  -- },
  -- {
  --   "obsidian-nvim/obsidian.nvim",
  --   -- version = "*", -- recommended, use latest release instead of latest commit
  --   lazy = true,
  --   -- ft = "markdown",
  --   -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
  --   event = {
  --     -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
  --     -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
  --     -- refer to `:h file-pattern` for more examples
  --     "BufReadPre */Obsidian/Vault/*.md",
  --     "BufNewFile */Obsidian/Vault/*.md",
  --   },
  --   dependencies = {
  --     -- Required.
  --     "nvim-lua/plenary.nvim",
  --
  --     -- see below for full list of optional dependencies 👇
  --   },
  --   opts = {
  --     workspaces = {
  --       {
  --         name = "Vault-Yin",
  --         path = "/mnt/c/Users/Lev/Obsidian/Vault",
  --       },
  --       {
  --         name = "Vault-Macos",
  --         path = "/Users/admin/Obsidian/Vault",
  --       },
  --     },
  --
  --     notes_subdir = "Fleeting",
  --
  --     completion = {
  --       nvim_cmp = false, -- disable!
  --       blink = false,
  --     },
  --
  --     -- see below for full list of options 👇
  --     picker = {
  --       name = "snacks.picker",
  --     },
  --     ui = {
  --       checkboxes = {
  --         ["-"] = { char = "󰰱", hl_group = "ObsidianStrikethrough" },
  --       },
  --       hl_groups = {
  --         ObsidianStrikethrough = { strikethrough = true, fg = "#505050" },
  --       },
  --     },
  --     disable_frontmatter = true,
  --     attachments = {
  --       img_folder = "Assets",
  --       -- Optional, customize the default name or prefix when pasting images via `:ObsidianPasteImg`.
  --       ---@return string
  --       img_name_func = function()
  --         -- Prefix image names with timestamp.
  --         return string.format("%Y-%m-%d %H.%M.%s", os.time())
  --       end,
  --       -- A function that determines the text to insert in the note when pasting an image.
  --       -- It takes two arguments, the `obsidian.Client` and an `obsidian.Path` to the image file.
  --       -- This is the default implementation.
  --       ---@param client obsidian.Client
  --       ---@param path obsidian.Path the absolute path to the image file
  --       ---@return string
  --       img_text_func = function(client, path)
  --         path = client:vault_relative_path(path) or path
  --         return string.format("![[%s]]", path.name, path)
  --       end,
  --     },
  --   },
  -- },
  -- {
  --   "folke/todo-comments.nvim",
  --
  --   opts = {
  --     keywords = {
  --       ["\\\\todo"] = { icon = "? ", color = "info" },
  --     },
  --   },
  -- },
  {
    "m4xshen/hardtime.nvim",
    enabled = false,
    lazy = false,
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      allow_different_key = false,
      restricted_keys = {
        ["h"] = { "n", "x" },
        ["j"] = { "n", "x" },
        ["k"] = { "n", "x" },
        ["l"] = { "n", "x" },
        ["<Up>"] = { "n", "x" },
        ["<Down>"] = { "n", "x" },
        ["<Left>"] = { "n", "x" },
        ["<Right>"] = { "n", "x" },
        ["+"] = { "n", "x" },
        ["gj"] = { "n", "x" },
        ["gk"] = { "n", "x" },
        ["<C-M>"] = { "n", "x" },
        ["<C-N>"] = { "n", "x" },
        ["<C-P>"] = { "n", "x" },
      },
      disabled_keys = {
        ["<Up>"] = false,
        ["<Down>"] = false,
        ["<Left>"] = false,
        ["<Right>"] = false,
      },
    },
  },
  -- {
  --   "MagicDuck/grug-far.nvim",
  --   -- opts = { headerMaxWidth = 80 },
  --   -- cmd = "GrugFar",
  --   keys = {
  --     {
  --       "<leader>sR",
  --       function()
  --         local grug = require("grug-far")
  --         local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
  --         grug.open({
  --           transient = true,
  --           prefills = {
  --             filesFilter = ext and ext ~= "" and "*." .. ext or nil,
  --           },
  --         })
  --       end,
  --       mode = { "n", "v" },
  --       desc = "Search and Replace",
  --     },
  --   },
  -- },
  {
    "folke/which-key.nvim",
    ---@type wk.Config
    opts = {
      spec = {
        { "<leader>m", group = "file modifications" },
        { "<leader>i", group = "insert commands", icon = { icon = " ", color = "orange" } },
        { "<leader>mc", icon = { icon = "󰊕", color = "blue" } },
        { "<leader>gw", group = "worktrees" },
      },
      icons = {
        rules = {
          { pattern = "insert", icon = " ", color = "orange" },
          { pattern = "function", icon = "󰊕", color = "blue" },
        },
      },
    },
  },
  {
    "hat0uma/csvview.nvim",
    ---@module "csvview"
    ---@type CsvView.Options
    opts = {
      parser = { comments = { "#", "//" } },
      keymaps = {
        -- Text objects for selecting fields
        textobject_field_inner = { "if", mode = { "o", "x" } },
        textobject_field_outer = { "af", mode = { "o", "x" } },
        -- Excel-like navigation:
        -- Use <Tab> and <S-Tab> to move horizontally between fields.
        -- Use <Enter> and <S-Enter> to move vertically between rows and place the cursor at the end of the field.
        -- Note: In terminals, you may need to enable CSI-u mode to use <S-Tab> and <S-Enter>.
        jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
        jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
        jump_next_row = { "<Enter>", mode = { "n", "v" } },
        jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
      },
    },
    cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
  },
  {
    dir = vim.fn.stdpath("config"),
    name = "extra_diff",
    lazy = true,
    cmd = { "GdscriptDiff" },
    config = function(_, opts)
      require("extra_diff").setup(opts)
    end,
  },
}
