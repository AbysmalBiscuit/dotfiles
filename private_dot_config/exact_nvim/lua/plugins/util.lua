-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---Deletes the selected session.
local function delete_session(picker, item)
  vim.fn.delete(item.session)
  picker:refresh()
end

local format_session = function(item, _)
  local a = Snacks.picker.util.align
  local ret = {} ---@type snacks.picker.Highlight[]
  if item.current then
    ret[#ret + 1] = { a("", 2), "SnacksPickerGitBranchCurrent" }
  else
    ret[#ret + 1] = { a("", 2) }
  end
  -- format = Snacks.picker.format.filename,
  ret[#ret + 1] = { a(item.dir, 100, { truncate = false }), "SnacksPickerFile" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { a(item.branch, 30, { truncate = true }), "SnacksPickerGitBranch" }
  -- ret[#ret + 1] = { a(item.sha, 8, { truncate = true }), "SnacksPickerGitCommit" }
  -- ret[#ret + 1] = { " " }
  -- ret[#ret + 1] = { a(item.path, 100, { truncate = true }), "SnacksPickerDirectory" }
  return ret
end

---@type LazyPluginSpec[]
return {
  {
    "folke/persistence.nvim",
    keys = {
      {
        "<leader>ql",
        function()
          local persistence = require("persistence")
          local is_windows = jit.os:find("Windows")
          Snacks.picker.pick(
            -- local picker = require("snacks.picker.core.picker").new(
            ---@type snacks.picker.Config
            {
              title = "Select a session",
              source = "sessions",

              ---@type snacks.picker.finder
              finder = function(opts, ctx)
                local persistence_config = require("persistence.config")
                local uv = vim.uv or vim.loop

                ---@type { session: string, dir: string, branch?: string }[]
                local items = {} ---@type snacks.picker.finder.Item[]
                local have = {} ---@type table<string, boolean>
                for _, session in ipairs(persistence.list()) do
                  if uv.fs_stat(session) then
                    local file = session:sub(#persistence_config.options.dir + 1, -5)
                    local dir, branch = unpack(vim.split(file, "%%", { plain = true }))
                    dir = dir:gsub("%%", "/")
                    if is_windows then
                      dir = dir:gsub("^(%w)/", "%1:/")
                    end
                    local current = false
                    if vim.fn.getcwd() == dir then
                      current = true
                    end
                    if not have[dir] then
                      have[dir] = true
                      items[#items + 1] = {
                        file = session,
                        session = session,
                        text = session,
                        dir = dir,
                        branch = branch,
                        current = current,
                      }
                    end
                  end
                end
                return ctx.filter:filter(items)
              end,
              preview = "none",
              format = format_session,
              layout = { hidden = { "preview" } },
              confirm = function(picker, item)
                picker:close()
                if item then
                  -- Wipe all current buffers to start fresh in the new worktree
                  -- Otherwise, your old files stay open alongside the new session
                  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
                      vim.api.nvim_buf_delete(bufnr, { force = false })
                    end
                  end
                  vim.fn.chdir(item.dir)
                  persistence.load()
                end
              end,
              actions = {
                delete_session = delete_session,
              },
              win = {
                input = {
                  keys = {
                    ["<c-x>"] = {
                      "delete_session",
                      mode = { "n", "i" },
                    },
                  },
                },
                list = {
                  keys = {
                    ["dd"] = "delete_session",
                  },
                },
              },
            }
          )
        end,
        desc = "Select Session",
      },
      {
        "<leader>qL",
        function()
          require("persistence").load()
        end,
        desc = "Restore Session",
      },
      {
        "<leader>qs",
        function()
          require("persistence").save()
        end,
        desc = "Save Current Session",
      },
    },
    opts = {
      branch = not vim.g.is_windows,
    },
  },
  {
    "nvzone/typr",
    dependencies = "nvzone/volt",
    lazy = true,
    opts = {},
    cmd = { "Typr", "TyprStats" },
  },
  {
    "gisketch/triforce.nvim",
    dependencies = {
      "nvzone/volt",
    },
    ---@type vim.api.keyset.events
    event = "UIEnter",
    cmd = {
      "TriForce",
      -- "TriForceStats",
    },
    opts = {
      keymap = nil,
    },
    config = function(_, opts)
      local triforce = require("triforce")
      triforce.setup(opts)
      vim.api.nvim_create_user_command("TriForce", function(args)
        local command = args.args
        if not command or command == "" then
          command = "profile"
        end

        if command == "profile" then
          return triforce.show_profile()
        elseif command == "debug" then
          return triforce.debug_languages()
        end
        vim.notify(
          "Received unknown command name: '" .. command .. "'.\n" .. "Available command names: 'profile', 'debug'",
          vim.log.levels.ERROR
        )
      end, {
        nargs = "?",
        desc = "Call basic triforce functions",
        complete = function(ArgLead, CmdLine, CursorPos)
          return { "profile", "debug" }
        end,
      })
      -- vim.api.nvim_create_user_command("TriForceStats", function(args)
      --   local command = args.args
      --   if not command or command == "" then
      --     vim.notify(
      --       "InsertHints needs a command name as an argument.\n"
      --         .. "Available command names: 'closest', 'line', 'visual', 'all'"
      --     )
      --     return
      --   end
      --
      --   if command == "show" then
      --     return triforce.get_stats()
      --   elseif command == "save" then
      --     return triforce.save_stats()
      --   elseif command == "reset" then
      --     return triforce.reset_stats()
      --   end
      --   vim.notify(
      --     "Received unknown command name: '" .. command .. "'.\n" .. "Available command names: 'profile', 'debug'",
      --     vim.log.levels.ERROR
      --   )
      -- end, {
      --   nargs = "?",
      --   desc = "Call triforce stats functions",
      --   complete = function(ArgLead, CmdLine, CursorPos)
      --     return { "show", "save", "reset" }
      --   end,
      -- })
    end,
  },
  {
    "xvzc/chezmoi.nvim",
    cmd = {
      "ChezmoiAdd",
    },
    opts = {
      edit = {
        ignore_patterns = {
          "run_onchange_.*",
          "run_once_.*",
          "%.chezmoiignore",
          "%.chezmoitemplate",
          ".chezmoiignore",
          ".chezmoi.toml.tmpl",
        },
      },
    },
    -- config = function(_, opts)
    --   local chezmoi = require("chezmoi")
    --   chezmoi.setup(opts)
    --
    --   vim.api.nvim_create_user_command("ChezmoiAdd", function()
    --     local file = vim.fn.expand("%:p")
    --     local args = { "chezmoi", "add" }
    --     if vim.fn.getftype(file) == "link" then
    --       table.insert(args, "--follow")
    --     end
    --     table.insert(args, file)
    --     vim.fn.system(args)
    --     vim.notify("Added to chezmoi: " .. file)
    --   end, { desc = "Add the current file to chezmoi" })
    --
    --   -- monkeypatch on wsl to use windows path to make lookPath work correctly
    --   local env = vim.fn.environ()
    --   if vim.g.is_wsl and env.PATH_CLEAN ~= nil and env.PATH_WINDOWS ~= nil then
    --     local notify = require("chezmoi.notify")
    --     local util = require("chezmoi.util")
    --     local Path = require("plenary.path")
    --     local Job = require("plenary.job")
    --     local config = require("chezmoi").config
    --
    --     local required_paths = {
    --       ".*Ollama.*",
    --     }
    --
    --     local windows_paths = vim.tbl_filter(
    --       ---@param path string Part of the path
    --       function(path)
    --         for i = 1, #required_paths do
    --           if path:match(required_paths[i]) then
    --             return true
    --           end
    --         end
    --         return false
    --       end,
    --       vim.split(env.PATH_WINDOWS, ":", { plain = true })
    --     )
    --
    --     env.PATH = env.PATH_CLEAN .. ":" .. table.concat(windows_paths, ":")
    --
    --     local chezmoi_execute = require("chezmoi.commands.__base")
    --     chezmoi_execute.execute = function(opts)
    --       vim.notify("custom exe")
    --       opts = opts or {}
    --       opts.targets = opts.targets or {}
    --       opts.args = opts.args or {}
    --       for _, v in ipairs(config.extra_args) do
    --         table.insert(opts.args, v)
    --       end
    --
    --       for i, v in ipairs(opts.targets) do
    --         local path = Path:new(v)
    --         opts.targets[i] = path:expand()
    --       end
    --
    --       opts.args = util.__normalize_args(opts.args)
    --
    --       if not opts.cmd then
    --         notify.panic("command not provided")
    --         return {}
    --       end
    --
    --       local on_stderr_default = function(_, data)
    --         error("'chezmoi " .. opts.cmd .. "'" .. "exited with an error:\n" .. data)
    --       end
    --
    --       local job = Job:new({
    --         command = "chezmoi",
    --         env = env,
    --         args = vim.iter({ opts.cmd, opts.targets, opts.args }):flatten():totable(),
    --         on_stderr = opts.on_stderr or on_stderr_default,
    --         on_exit = opts.on_exit,
    --       })
    --
    --       job:sync()
    --
    --       return job:result()
    --     end
    --   end
    -- end,
  },
}
