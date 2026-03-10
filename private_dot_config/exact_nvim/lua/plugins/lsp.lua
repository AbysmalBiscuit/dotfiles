-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

-- vim.lsp.config("*", {
--   capabilities = {
--     -- textDocument = {
--     --   semanticTokens = {
--     --     multilineTokenSupport = true,
--     --   },
--     -- },
--     general = {
--       positionEncodings = { "utf-16" },
--     },
--     offsetEncoding = { "utf-16" },
--   },
--   -- root_markers = { ".git" },
--   offsetEncoding = { "utf-16" },
-- })

---@type LazyPluginSpec[]
return {
  {
    "neovim/nvim-lspconfig",
    keys = {
      -- {
      --   "<C-.>",
      --   vim.lsp.buf.code_action,
      --   desc = "Code Action",
      --   mode = { "n", "v" },
      -- },
      {
        "<C-.>",
        function()
          local curr_row = vim.api.nvim_win_get_cursor(0)[1]
          vim.lsp.buf.code_action({ ["range"] = { ["start"] = { curr_row, 0 }, ["end"] = { curr_row, 65535 } } })
        end,
        mode = { "n", "i", "v" },
        desc = "Code action",
      },
      {
        "<M-.>",
        vim.lsp.buf.code_action,
        mode = { "n", "i" },
        desc = "Code action",
      },
    },
    ---@class PluginLspOpts
    opts = {

      diagnostics = {
        float = { border = "rounded" },
        virtual_text = true,
      },
      inlay_hints = {
        enabled = true,
        exclude = {
          "tex",
          "latex",
        },
      },
      document_highlight = {
        enabled = false,
      },
      ---@type table<string, lazyvim.lsp.Config|boolean>
      servers = {
        ["*"] = {
          capabilities = {
            semanticTokensProvider = false,
            workspace = {
              fileOperations = {
                didRename = true,
                willRename = true,
              },
            },
          },
          -- stylua: ignore
          keys = {
            -- { "<leader>cl", function() Snacks.picker.lsp_config() end, desc = "Lsp Info" },
            -- { "gd", vim.lsp.buf.definition, desc = "Goto Definition", has = "definition" },
            -- { "gr", vim.lsp.buf.references, desc = "References", nowait = true },
            -- { "gI", vim.lsp.buf.implementation, desc = "Goto Implementation" },
            -- { "gy", vim.lsp.buf.type_definition, desc = "Goto T[y]pe Definition" },
            -- { "gD", vim.lsp.buf.declaration, desc = "Goto Declaration" },
            -- { "K", function() return vim.lsp.buf.hover({ border = "rounded" }) end, desc = "Hover" },
            -- { "gK", function() return vim.lsp.buf.signature_help({ border = "rounded" }) end, desc = "Signature Help", has = "signatureHelp" },
            -- { "<c-k>", function() return vim.lsp.buf.signature_help({ border = "rounded" }) end, mode = "i", desc = "Signature Help", has = "signatureHelp" },
            -- { "<leader>ca", vim.lsp.buf.code_action, desc = "Code Action", mode = { "n", "x" }, has = "codeAction" },
            -- { "<leader>cc", vim.lsp.codelens.run, desc = "Run Codelens", mode = { "n", "x" }, has = "codeLens" },
            -- { "<leader>cC", vim.lsp.codelens.refresh, desc = "Refresh & Display Codelens", mode = { "n" }, has = "codeLens" },
            -- { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename File", mode ={"n"}, has = { "workspace/didRenameFiles", "workspace/willRenameFiles" } },
            -- { "<leader>cr", vim.lsp.buf.rename, desc = "Rename", has = "rename" },
            -- { "<leader>cA", LazyVim.lsp.action.source, desc = "Source Action", has = "codeAction" },
            -- { "]]", function() Snacks.words.jump(vim.v.count1) end, has = "documentHighlight",
            --   desc = "Next Reference", enabled = function() return Snacks.words.is_enabled() end },
            -- { "[[", function() Snacks.words.jump(-vim.v.count1) end, has = "documentHighlight",
            --   desc = "Prev Reference", enabled = function() return Snacks.words.is_enabled() end },
            -- { "<a-n>", function() Snacks.words.jump(vim.v.count1, true) end, has = "documentHighlight",
            --   desc = "Next Reference", enabled = function() return Snacks.words.is_enabled() end },
            -- { "<a-p>", function() Snacks.words.jump(-vim.v.count1, true) end, has = "documentHighlight",
            --   desc = "Prev Reference", enabled = function() return Snacks.words.is_enabled() end },
          },
        },
      },
    },
  },
  -- { "davidmh/cspell.nvim" },
  {
    "barreiroleo/ltex_extra.nvim",
    branch = "dev",
    -- lazy = true,
    ft = { "markdown", "plaintex", "rst", "tex", "latex" },
    opts = {
      load_langs = { "en-US" },
      -- save to .ltex dir
      path = ".ltex",
      -- path = function()
      --   local file_path = vim.api.nvim_buf_get_name(0)
      --   local root_pattern = require("lspconfig").util.root_pattern
      --   -- Look for existing `.ltex` directory first. If it doesn't exist,
      --   -- look for .git/.hg directories. If everything else fails, get absolute path to the file parent
      --   return root_pattern(".ltex", ".hg", ".git")(file_path) or vim.fn.fnamemodify(file_path, ":p:h")
      -- end,
    },
  },
  -- {
  --   "nvimtools/none-ls.nvim",
  --   event = "VeryLazy",
  --   cmd = {
  --     "NullLsToggle",
  --   },
  --   depends = { "davidmh/cspell.nvim" },
  --   opts = function(_, opts)
  --     vim.api.nvim_create_user_command("NullLsToggle", function(args)
  --       -- vim.notify(vim.inspect(args.args))
  --       require("null-ls").toggle(args.args)
  --     end, { nargs = 1 })
  --
  --     local cspell = require("cspell")
  --     ---@type CSpellSourceConfig
  --     local config = {
  --       cspell_config_dirs = { "~/.config/cspell" },
  --       read_config_synchronously = false,
  --     }
  --     opts.sources = opts.sources or {}
  --     table.insert(
  --       opts.sources,
  --       cspell.diagnostics.with({
  --         config = config,
  --         diagnostics_postprocess = function(diagnostic)
  --           diagnostic.severity = vim.diagnostic.severity.HINT
  --         end,
  --       })
  --     )
  --     -- table.insert(opts.sources, cspell.code_actions)
  --     table.insert(
  --       opts.sources,
  --       cspell.code_actions.with({
  --         config = config, -- Pass the config here
  --         -- filetypes = { "markdown", "text", "gitcommit", "lua", "javascript", "typescript", "json", "yaml" },
  --       })
  --     )
  --
  --     -- vim.cmd("NullLsToggle cspell")
  --   end,
  -- },
  -- {
  --   "lervag/vimtex",
  --   lazy = false, -- lazy-loading will disable inverse search
  --   -- config = function()
  --   --   vim.g.vimtex_mappings_disable = { ["n"] = { "K" } } -- disable `K` as it conflicts with LSP hover
  --   --   vim.g.vimtex_quickfix_method = vim.fn.executable("pplatex") == 1 and "pplatex" or "latexlog"
  --   -- end,
  --   -- keys = {
  --   --   { "<localLeader>l", "", desc = "+vimtex", ft = "tex" },
  --   -- },
  -- },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
  },
  -- {
  --   "nvimdev/lspsaga.nvim",
  --   event = "LspAttach",
  --   dependencies = {
  --     -- "nvim-treesitter/nvim-treesitter", -- optional
  --     -- "nvim-tree/nvim-web-devicons", -- optional
  --   },
  --   config = {
  --     finder = {},
  --   },
  -- },
  -- {
  --   "zbirenbaum/copilot.lua",
  --   opts = {
  --     server_opts_overrides = {
  --       settings = {
  --         telemetry = {
  --           telemetryLevel = "off",
  --         },
  --       },
  --     },
  --   },
  -- },
  {
    "jmbuhr/otter.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = { "ToggleOtter" },
    opts = {},
    config = function(_, opts)
      local otter = require("otter")
      local otter_active = false
      otter.setup(opts)
      vim.api.nvim_create_user_command("ToggleOtter", function()
        local otter_status
        if otter_active then
          otter.deactivate()
          otter_status = "disabled"
        else
          otter_status = "enabled"
          otter.activate()
        end
        vim.notify("otter set to " .. otter_status)
      end, opts)
    end,
  },
}
