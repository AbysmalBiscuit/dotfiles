-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

-- local function return_to_calling_window(current_win)
--   -- local current_win = vim.api.nvim_get_current_win() -- Capture the current window
--   vim.cmd("stopinsert")
--   vim.defer_fn(function()
--     if vim.api.nvim_win_is_valid(current_win) then
--       vim.api.nvim_set_current_win(current_win) -- Return to the captured window;
--     end
--   end, 10)
-- end

---@type LazyPluginSpec[]
return {
  {
    -- https://github.com/akinsho/toggleterm.nvim
    "akinsho/toggleterm.nvim",
    lazy = true,
    enabled = true,
    cmd = {
      "ToggleTerm",
      "ToggleTermSendCurrentLine",
      "ToggleTermSendVisualLines",
      "ToggleTermSendVisualSelection",
      "ToggleTermSetName",
      "ToggleTermToggleAll",
    },
    keys = {
      "<F5>",
      "<cmd>lua run_script()<CR>",
      modes = { "n", "i" },
      noremap = true,
      -- silent = true,
      desc = "Run current file in a toggleterm terminal",
    },
    opts = {
      direction = "horizontal", -- "horizontal", "vertical", "tab", or "float"
      size = 15, -- Height of terminal split
      open_mapping = [[<C-\>]], -- Key to toggle the terminal
      -- on_open = function(term)
      --   -- Prevent focusing the terminal
      --   vim.cmd("stopinsert")
      --   vim.defer_fn(function()
      --     vim.cmd("wincmd p") -- Go back to the previous window
      --   end, 10) -- Delay to ensure the terminal finishes opening
      -- end,
      shade_terminals = false,
      highlights = {
        Normal = {
          guibg = "#141F2E",
          ctermbg = "NONE",
        },
        NormalNC = {
          guibg = "#0D141F",
        },
      },
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)
      local Terminal = require("toggleterm.terminal").Terminal

      -- Define the IPython command with autoreload setup
      -- local ipython_cmd = table.concat({
      --   "ipython",
      --   "--no-autoindent",
      --   '--InteractiveShellApp.exec_lines="%load_ext autoreload"',
      --   '--InteractiveShellApp.exec_lines="%autoreload 2"',
      -- }, " ")

      local run_term_exited = false
      local python_shell_cmd = "python3 -i -c 'import runpy'"
      local python_cmd = 'runpy.run_path("%s", globals())'

      if vim.fn.executable("ipython") == 1 then
        if vim.fn.executable(".venv/bin/ipython") == 1 then
          python_shell_cmd = ".venv/bin/ipython"
        else
          python_shell_cmd = "ipython"
        end
        python_shell_cmd = string.format(
          "%s --no-autoindent --InteractiveShellApp.exec_lines='%%load_ext autoreload' --InteractiveShellApp.exec_lines='%%autoreload 2'",
          python_shell_cmd
        )
        python_cmd = '%%run -t "%s"'
      end

      local shell_commands = {
        python = python_shell_cmd,
        lua = "lua",
        fish = "fish",
        sh = "bash",
        javascript = "node",
      }

      local commands = {
        python = python_cmd,
        javascript = ".load '%s'",
        -- javascript = "bun '%s'",
        lua = "os.execute('lua \"%s\"')",
        sh = "bash '%s'",
        fish = "fish '%s'",
      }

      -- Node doesn't seem to work properly
      local non_interactive = {
        javascript = "bun run %s",
      }

      local last_run_filetype
      ---@type Terminal | nil
      local run_terminal = nil
      local calling_window
      local current_mode
      local function restore_context()
        -- Small defer ensures the terminal focus event finishes before we snatch focus back
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(calling_window) then
            vim.api.nvim_set_current_win(calling_window)

            -- ONLY go to insert mode if we started there
            if current_mode:sub(1, 1) ~= "n" then
              vim.cmd("stopinsert")
            else
              vim.cmd("startinsert")
            end
          end
        end)
      end

      -- Function to dynamically run scripts based on file type
      _G.run_script = function()
        calling_window = vim.api.nvim_get_current_win()
        current_mode = vim.api.nvim_get_mode().mode

        -- Save the current buffer before running the script
        vim.cmd("write")
        local filepath = vim.fn.expand("%:p"):gsub("\\", "/")
        local filetype = vim.bo.filetype

        -- For non-Python file types, create or reuse a generic terminal
        local shell_cmd = shell_commands[filetype]
        local cmd = commands[filetype]
        local non_interactive = non_interactive[filetype]

        if not shell_cmd then
          print("No shell command configured for filetype: " .. filetype)
          return
        end
        if not cmd then
          print("No run command configured for filetype: " .. filetype)
          return
        end

        cmd = string.format(cmd, filepath)
        if non_interactive ~= nil then
          non_interactive = string.format(non_interactive, filepath)
        end

        if filetype == "lua" then
          -- if running lua test files, use a different command
          if string.match(filepath, ".*_spec.lua") then
            if vim.fn.executable("busted") == 1 then
              cmd = string.format("os.execute('busted \"%s\"')", filepath)
            else
              cmd = string.format("os.execute('luarocks --local test \"%s\"')", filepath)
            end
          else
            cmd = string.format(cmd, filepath)
          end
        end

        -- If last command exited, close terminal so the file can be re-run
        if
          run_terminal
          and (run_term_exited or (last_run_filetype and last_run_filetype ~= filetype) or non_interactive ~= nil)
        then
          run_term_exited = false
          run_terminal:shutdown()
          run_terminal = nil
        end

        -- Create or reuse a generic terminal
        if non_interactive ~= nil then
          run_terminal = Terminal:new({
            cmd = non_interactive,
            direction = "horizontal",
            on_open = function(term)
              restore_context()
            end,
            close_on_exit = false,
            ---@type fun(t: Terminal, job: number, exit_code: number, name: string)
            on_exit = function(_, _, _, _)
              do
                run_term_exited = true
              end
            end,
          })
          last_run_filetype = filetype
          run_terminal:toggle()
        elseif not run_terminal then
          run_terminal = Terminal:new({
            cmd = shell_cmd,
            direction = "horizontal",
            close_on_exit = false,
            ---@type fun(t: Terminal, job: number, exit_code: number, name: string)
            on_exit = function(_, _, _, _)
              do
                run_term_exited = true
              end
            end,
          })
          last_run_filetype = filetype
          run_terminal:toggle()

          run_terminal:send(cmd, true)
        elseif run_terminal:is_open() then
          run_terminal:send(cmd, true)
        else
          run_terminal:toggle()
          run_terminal:send(cmd, true)
        end
      end

      -- Keybinding to run the current file
      vim.keymap.set({ "n", "i" }, "<F5>", "<cmd>lua run_script()<CR>", { noremap = true, silent = true })
    end,
  },
  -- {
  --   "yarospace/lua-console.nvim",
  --   lazy = true,
  --   cmd = {
  --     "Luaconsole",
  --   },
  --   keys = {
  --     { "`", false },
  --     { "<leader>`", false },
  --   },
  --   -- keys = {
  --   --   { "`", desc = "Lua-console - toggle" },
  --   --   { "<Leader>`", desc = "Lua-console - attach to buffer" },
  --   -- },
  --   opts = {
  --     mappings = {
  --       toggle = false,
  --       resize_up = "<C-S-Up>",
  --       resize_down = "<C-S-Down>",
  --     },
  --   },
  --   config = function(_, opts)
  --     local lua_console = require("lua-console")
  --     lua_console.setup(opts)
  --
  --     vim.api.nvim_create_user_command("Luaconsole", function(_, _, _)
  --       lua_console.toggle_console()
  --     end, {
  --       desc = "Toggle Lua-console",
  --     })
  --   end,
  -- },
  -- {
  --   -- https://github.com/linux-cultist/venv-selector.nvim/tree/regexp
  --   "linux-cultist/venv-selector.nvim",
  --   -- "stefanboca/venv-selector.nvim",
  --   dependencies = {
  --     "neovim/nvim-lspconfig",
  --     "mfussenegger/nvim-dap",
  --     "mfussenegger/nvim-dap-python",
  --     -- { "nvim-telescope/telescope.nvim", branch = "0.1.x", dependencies = { "nvim-lua/plenary.nvim" } },
  --   },
  --   enabled = true,
  --   command = "VenvSelect",
  --   lazy = false,
  --   -- branch = "regexp", -- This is the regexp branch, use this for the new version
  --   -- branch = "sb/push-rlpxsqmllxtz",
  --   -- event = "VeryLazy",
  --   -- config = function()
  --   --   require("venv-selector").setup()
  --   -- end,
  --   -- keys = {
  --   --   {
  --   --     "<leader>venv",
  --   --     "<cmd>VenvSelect<CR>",
  --   --     desc = "Select python virtual environment",
  --   --   },
  --   -- },
  -- },
}
