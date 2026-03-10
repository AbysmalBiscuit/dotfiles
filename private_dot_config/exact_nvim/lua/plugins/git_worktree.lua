-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

--- @class WorktreeItem: snacks.picker.finder.Item
--- @field cwd string CWD path.
--- @field detached boolean Whether the item is a detached HEAD.
--- @field branch string? The branch.
--- @field path string Worktree path. Empty string if not a worktree.
--- @field current boolean True if the currently checked out branch.
--- @field commit string Commit hash
--- @field upstream string Upstream branch if different
--- @field msg string

--- @class WorktreeCreationResult
--- @field path string
--- @field ref_branch string
--- @field new_branch_name string?
--- @field remote string?
--- @field detached boolean
--- @field create_new_branch "-b" | nil
--- @field detached_arg "--detached" | nil

-- Global variables used by the module
vim.g.git_worktree_default_dir = "./.worktrees/"
local max_worktree_path = 0
local max_branch_name = 0
local force_next_deletion = false
local tried_forced_deletion = false

--- Gets local and remote branches, cleans up the "*" and whitespace
local function get_git_branches()
  local branches = vim.fn.systemlist("git branch -a --format='%(refname:short)'")
  return vim.tbl_filter(function(b)
    return b ~= ""
  end, branches)
end

--- Selects the picker item in ui based on branch name
--- @param picker snacks.Picker
--- @param workspace_info WorktreeCreationResult
local function select_picker_item(picker, workspace_info)
  ---@type WorktreeItem[]
  local items = picker:items()
  for _, item in ipairs(items) do
    if item.path == workspace_info.path and item.branch == workspace_info.ref_branch then
      vim.notify("found new item")
      picker:resolve(item)
    end
  end
end

--- --- Gets longest string in a table
--- local function get_longest_string(tbl)
---   local longest = ""
---   for _, s in ipairs(tbl) do
---     if #s > #longest then
---       longest = s
---     end
---   end
---   return longest
--- end

--- Filters table to only include non-nil and not empty string values
local function filter_command(tbl)
  local filtered = {}
  for _, value in pairs(tbl) do
    if value ~= nil and value ~= "" then
      table.insert(filtered, value)
    end
  end
  return filtered
end

-- local function get_top_level_dir()
--   local result = vim.system({ "git", "rev-parse", "--path-format=absolute", "--show-toplevel" }):wait()
--   if result.code ~= 0 then
--     vim.notify("Failed to identify git top level dir", "error")
--     return nil
--   end
--   return result.stdout:sub(1, string.len(result.stdout) - 1)
-- end

local function get_main_repo_root()
  -- Get the common .git directory path
  local git_dir = vim.fn.systemlist("git rev-parse --path-format=absolute --git-common-dir")[1]

  if not git_dir or git_dir == "" then
    return nil
  end

  -- Use :h to get the parent of the .git directory
  return vim.fn.fnamemodify(git_dir, ":h")
end

--- --- Gets existing worktree paths
--- --- @param cwd string? Path to the CWD, can be nil.
--- local function get_worktree_paths(cwd)
---   local worktrees = vim.fn.systemlist("git worktree list")
---   local top_level_dir = cwd or Snacks.git.get_root()
---
---   local cleaned_paths = {}
---   for _, path in ipairs(worktrees) do
---     local clean = vim.split(path, "%s")[1]
---     if clean ~= top_level_dir then
---       table.insert(cleaned_paths, vim.split(path, "%s")[1])
---     end
---   end
---   return cleaned_paths
--- end

--- Create a git worktree.
--- Either `path` or `branch` must be passed.
--- @param path string | nil Path in which to create the worktree.
--- @param ref_branch string | nil Name of branch to use. Can be nil to use the current branch.
--- @param new_branch_name string | nil Name of the new branch to create.
--- @param remote string | nil Name of remote to use. Can be nil to use the same remote as the branch.
--- @param detached boolean | nil If true, then create a detached HEAD worktree. If false, try to create a normal worktree.
--- @return { path: string, ref_branch: string, new_branch_name: string?, remote: string?, detached: boolean, create_new_branch: "-b" | nil, detached_arg: "--detached" | nil, } Returns a table with relevant parameters. Useful for selecting the newly created worktree in the picker UI.
--- @usage create_worktree("path/to/worktree", "my-feature", "special-remote")
local function create_worktree(path, ref_branch, new_branch_name, remote, detached)
  path = path or ""
  ref_branch = ref_branch or ""
  remote = remote or ""
  detached = detached or false

  -- vim.notify("initial args: " .. vim.inspect({
  --   path = string.format("%s", path),
  --   ref_branch = string.format("%s", ref_branch),
  --   new_branch_name = string.format("%s", new_branch_name),
  --   remote = string.format("%s", remote),
  --   detached = string.format("%s", detached),
  -- }))
  if path == "" and ref_branch == "" then
    vim.notify("Either path or branch must be passed", "error")
    return {}
  elseif path == vim.g.git_worktree_default_dir and ref_branch == "" and not detached then
    vim.notify("branch must be specified when passing only the default worktree path", "error")
    return {}
  end

  if path == vim.g.git_worktree_default_dir then
    if new_branch_name ~= nil and new_branch_name ~= "" then
      path = path .. new_branch_name
    else
      path = path .. ref_branch
    end
  end

  -- local new_branch_name = nil
  if path == "" then
    path = ref_branch
    -- elseif new_branch_name == "" then
    --   local name_split = vim.split(path, "/")
    --   new_branch_name = name_split[#name_split]
  end

  local create_new_branch = nil
  if ref_branch ~= "" and new_branch_name ~= "" then
    local all_branches = get_git_branches()
    if not vim.tbl_contains(all_branches, new_branch_name) then
      create_new_branch = "-b"
    else
      new_branch_name = nil
    end
  end

  if new_branch_name == nil then
    create_new_branch = nil
  end

  if remote == "" then
    remote = nil
  end

  local detached_arg = detached and "--detached" or nil

  -- vim.notify("before command call: " .. vim.inspect({
  --   path = string.format("%s", path),
  --   ref_branch = string.format("%s", ref_branch),
  --   new_branch_name = string.format("%s", new_branch_name),
  --   remote = string.format("%s", remote),
  --   detached = string.format("%s", detached),
  --   create_new_branch = string.format("%s", create_new_branch),
  --   detached_arg = string.format("%s", detached_arg),
  -- }))

  local command = filter_command({
    "git",
    "worktree",
    "add",
    detached_arg,
    create_new_branch,
    new_branch_name,
    path,
    ref_branch,
    remote,
  })

  -- vim.notify(vim.inspect(command))
  -- local com = ""
  -- for _, item in ipairs(command) do
  --   if item ~= nil then
  --     com = com .. " " .. item
  --   end
  -- end
  -- vim.notify(com)

  local result = vim.system(command):wait()

  if result.code ~= 0 then
    vim.notify(result.stderr, "error")
    vim.notify(vim.inspect(command))
  end

  return {
    path = path,
    ref_branch = ref_branch,
    new_branch_name = new_branch_name,
    remote = remote,
    detached = detached,
    create_new_branch = create_new_branch,
    detached_arg = detached_arg,
  }
end

--- Switch to the selected worktree
--- @param picker snacks.Picker Picker instance.
--- @param item WorktreeItem Item to be formatted.
--- @return nil
local function switch_worktree(picker, item)
  if not item then
    return
  end

  if item.path == "" then
    -- vim.notify("No worktree defined for branch " .. item.branch)
    vim.notify("Creating worktree and switching to it " .. item.branch)
    local worktree_path = vim.g.git_worktree_default_dir .. item.branch
    if worktree_path:sub(1, 1) == "." then
      worktree_path = get_main_repo_root() .. "/" .. worktree_path
    end
    -- vim.notify(worktree_path)
    -- vim.notify(get_main_repo_root())
    -- return
    create_worktree(worktree_path, item.branch, nil, nil, false)
    item.path = worktree_path
  end

  -- if item.path == "" and item.branch ~= "" then
  --   Snacks.picker.actions.git_checkout(picker, item)
  --   return
  -- end

  local persistence = require("persistence")

  -- Save the session for the current worktree before leaving
  persistence.save()

  -- Stop saving the session to avoid overwriting it
  persistence.stop()

  -- Create a session in the new worktree
  local persistence_config = require("persistence.config")
  local is_windows = jit.os:find("Windows")
  local uv = vim.uv or vim.loop
  local has_session = false
  for _, session in ipairs(persistence.list()) do
    if uv.fs_stat(session) then
      local file = session:sub(#persistence_config.options.dir + 1, -5)
      local dir, branch = unpack(vim.split(file, "%%", { plain = true }))
      dir = dir:gsub("%%", "/")
      if is_windows then
        dir = dir:gsub("^(%w)/", "%1:/")
      end
      if dir == item.path then
        has_session = true
        break
      end
    end
  end
  if not has_session then
    local result = vim
      .system(
        { "nvim", "--headless", "-i", "NONE", "-c", "lua require('persistence').save()", "-c", "qa" },
        { cwd = item.path }
      )
      :wait()

    if result.code ~= 0 then
      vim.notify("Error with creating a session in the worktree: " .. item.path, "error")
      vim.notify(vim.inspect(result))
      return nil
    end
  end

  vim.schedule(function()
    local lsp_clients = vim.lsp.get_clients()
    for _, client in ipairs(lsp_clients) do
      if not client:is_stopped() then
        client:stop(true)
      end
    end
  end)

  picker:close()
  Snacks.notify.info("Switching to " .. item.path)

  -- Wipe all current buffers to start fresh in the new worktree
  -- Otherwise, your old files stay open alongside the new session
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      vim.api.nvim_buf_delete(bufnr, { force = false })
    end
  end

  -- 3. Load the session for the new worktree
  vim.schedule(function()
    vim.fn.chdir(item.path)
    persistence.load()
    persistence.start()

    -- Check if we ended up with no files open
    local bufs = vim.api.nvim_list_bufs()
    local has_open_files = false

    for _, bufnr in ipairs(bufs) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted and vim.api.nvim_buf_get_name(bufnr) ~= "" then
        has_open_files = true
        break
      end
    end

    if not has_open_files then
      Snacks.dashboard.open()
      vim.fn.execute("redraw")
    end
  end)
end

--- Toggle the forced deletion of the next worktree
--- @return nil
local toggle_forced_deletion = function()
  -- redraw otherwise the message is not displayed when in insert mode
  if force_next_deletion then
    vim.notify("The next deletion will not be forced")
    vim.fn.execute("redraw")
  else
    vim.notify("The next deletion will be forced")
    vim.fn.execute("redraw")
    force_next_deletion = true
  end
end

--- Snacks confirm
--- @param prompt string Prompt to display
--- @param cb fun() Callback function if confirmed
--- @return nil
local snacks_confirm = function(prompt, cb)
  Snacks.picker.select({ "Yes", "No" }, { prompt = prompt }, function(_, idx)
    -- idx == 1 means Yes was picked
    -- idx == 2 means No was picked
    if idx == 1 then
      cb()
    end
  end)
end

--- @param picker snacks.Picker
--- @param item WorktreeItem
--- @param opts? table
local function delete_branch(picker, item, opts)
  opts = opts or {}
  if not tried_forced_deletion then
    force_next_deletion = false
  end
  local prompt = opts.prompt or "Worktree deleted, delete branch?"
  if force_next_deletion then
    prompt = "Worktree deleted, now force deletion of branch?"
  end
  if item.branch ~= nil and item.branch ~= "HEAD" then
    snacks_confirm(prompt, function()
      local delete = "--delete"
      if force_next_deletion then
        vim.notify("Trying to force deletion")
        delete = "-D"
      end
      tried_forced_deletion = true
      force_next_deletion = false
      local result = vim.system({ "git", "branch", delete, item.branch }):wait()
      if result.code == 0 then
        vim.notify("Branch deleted")
        picker:refresh()
      else
        vim.notify(result.stderr, "error")
      end
    end)
  end
end

--- Delete the selected worktree
--- @param picker snacks.Picker Picker instance.
--- @param item WorktreeItem Item to be formatted.
--- @return nil
local function delete_worktree(picker, item)
  if not item then
    Snacks.notify.warn("No worktree to delete", { title = "Snacks Picker" })
  end

  local worktree_path = item.path
  local prompt = "Delete worktree %q?"
  if force_next_deletion then
    prompt = "Force deletion of worktree %q?"
  end
  prompt = (prompt):format(worktree_path)

  if worktree_path ~= "" then
    snacks_confirm(prompt, function()
      local force = force_next_deletion and "--force" or nil
      local command = filter_command({ "git", "worktree", "remove", force, worktree_path })
      local result = vim.system(command):wait()
      if result.code == 0 then
        vim.notify("worktree removed")
        picker:refresh()
        delete_branch(picker, item, nil)
      else
        vim.notify("Deletion failed, try to use <C-f> to force the next deletion", "error")
        -- vim.notify(result.stderr, "error")
      end
    end)
  elseif item.branch ~= "" then
    delete_branch(picker, item, { branch = item.branch, prompt = "No worktree, delete branch?" })
  end
end

--- @param picker snacks.Picker Picker instance.
--- @param item WorktreeItem Item to be formatted.
--- @return nil
local get_worktree_name_and_create_it = function(picker, item)
  if not item then
    vim.notify("No item provided for creating worktree", "error")
  end

  vim.ui.input({
    prompt = "Path to worktree",
    default = vim.g.git_worktree_default_dir,
  }, function(worktree_path)
    local workspace_info = create_worktree(worktree_path, item.branch, item.new_branch_name, nil, item.detached)
    picker:refresh()
    select_picker_item(picker, workspace_info)
  end)
end

--- Create a new worktree with a new branch
--- @param picker snacks.Picker Picker instance.
--- @param item WorktreeItem Item to be formatted.
--- @return nil
local function add_new_branch_and_worktree(picker, item)
  item.detached = false
  vim.ui.input({
    prompt = "New branch name",
    default = "",
  }, function(new_branch_name)
    if new_branch_name ~= "" then
      item.new_branch_name = new_branch_name
      get_worktree_name_and_create_it(picker, item)
    end
  end)
end

--- Formatter used for the Snacks picker
--- @param picker snacks.Picker Picker instance.
--- @param item WorktreeItem Item to be formatted.
--- @return nil
local function add_new_detached_head_worktree(picker, item)
  item.detached = true
  get_worktree_name_and_create_it(picker, item)
end

--- Formatter used for the Snacks picker
--- @param item WorktreeItem Item to be formatted.
--- @param picker snacks.Picker Picker instance.
--- @return table
local function format_dir(item, picker)
  local dir_hl = "SnacksPickerDir"
  local base_hl = "SnacksPickerDirectory"
  return {
    [1] = {
      "",
      resolve = function(max_width)
        local truncpath = Snacks.picker.util.truncpath(
          item.path,
          math.max(max_width, picker.opts.formatters.file.min_width or 20, max_worktree_path),
          { cwd = picker:cwd(), kind = picker.opts.formatters.file.truncate }
        )

        local dir, base = truncpath:match("^(.*)/(.+)$")
        -- vim.notify(string.format("'%s' '%s' '%s'", item.path, dir, base))
        local resolved = {} ---@type snacks.picker.Highlight[]
        if base and dir then
          resolved[#resolved + 1] = { dir .. "/", dir_hl, field = "file" }
          resolved[#resolved + 1] = { base, base_hl, field = "file" }
          local current_length = #resolved[1][1] + #resolved[2][1]
          if current_length < max_worktree_path then
            resolved[#resolved + 1] = { string.rep(" ", max_worktree_path - current_length + 1) }
          end
        else
          resolved[#resolved + 1] = { truncpath, base_hl, field = "file" }
          local current_length = #resolved[1][1]
          if current_length < max_worktree_path then
            resolved[#resolved + 1] = { string.rep(" ", max_worktree_path - current_length + 1) }
          end
        end
        return resolved
      end,
    },
  }
end

vim.keymap.set("n", "<leader>gw", function()
  if not Snacks then
    return
  end

  Snacks.picker.pick({
    all = false,
    finder = function(opts, ctx)
      local args = {
        "branch",
        "--format=%(HEAD)|%(refname:short)|%(worktreepath)|%(upstream:trackshort)|%(objectname:short)|%(contents:subject)",
      }
      local uv = vim.uv or vim.loop
      ---@type string?
      local cwd = vim.fs.normalize(opts and opts.cwd or uv.cwd() or ".") or nil
      cwd = Snacks.git.get_root(cwd) or ""

      -- local worktrees = get_worktree_paths()
      -- local trimmed_worktrees = {}
      --
      -- for _, path in ipairs(worktrees) do
      --   if path:sub(1, #cwd) == cwd then
      --     table.insert(trimmed_worktrees, path:sub(#cwd + 1))
      --   else
      --     table.insert(trimmed_worktrees, path)
      --   end
      -- end

      -- max_worktree_path = math.max(#vim.fn.fnamemodify(cwd, ":t"), #get_longest_string(trimmed_worktrees))

      max_worktree_path = 0
      max_branch_name = 0

      local new_opts = vim.tbl_deep_extend("force", opts or {}, {
        cwd = cwd,
        cmd = "git",
        args = args,
        ---@param item WorktreeItem
        transform = function(item)
          item.cwd = cwd
          local head, branch, worktree, upstream, commit, msg = unpack(vim.split(item.text, "|"))
          item.detached = string.match(branch, "(%b())")
          item.head = head
          item.branch = not item.detached and branch or nil
          item.path = worktree ~= cwd and worktree or ""
          item.current = head == "*"
          item.commit = commit
          item.upstream = upstream
          item.msg = msg

          -- Update longest string values
          local trimmed_worktree = worktree:sub(1, #cwd)
          if trimmed_worktree == cwd and #trimmed_worktree > max_worktree_path then
            max_worktree_path = #trimmed_worktree
          end

          if #branch > max_branch_name then
            max_branch_name = #branch
          end

          -- 15 is the length of the "(detached HEAD)" string
          if item.detached and max_branch_name < 15 then
            max_branch_name = 15
          end

          if item.msg == "(bare)" then
            return false
          end
        end,
      })

      return require("snacks.picker.source.proc").proc(new_opts, ctx)
    end,
    ---@param item WorktreeItem
    format = function(item, picker)
      local a = Snacks.picker.util.align
      local ret = {} ---@type snacks.picker.Highlight[]
      if item.current then
        ret[#ret + 1] = { a("", 2), "SnacksPickerGitBranchCurrent" }
      else
        ret[#ret + 1] = { a("", 2) }
      end

      if item.detached then
        ret[#ret + 1] = { a("(detached HEAD)", max_branch_name, { truncate = true }), "SnacksPickerGitDetached" }
      else
        ret[#ret + 1] = { a(item.branch, max_branch_name, { truncate = true }), "SnacksPickerGitBranch" }
      end

      ret[#ret + 1] = { " " }

      if item.path ~= "" then
        ret[#ret + 1] = { a("", 2), "SnacksPickerGitStatusAdded" }
        Snacks.picker.highlight.extend(ret, format_dir(item, picker))
      else
        ret[#ret + 1] = { a("", 2) }
        Snacks.picker.highlight.extend(ret, format_dir({ path = item.cwd }, picker))
      end

      ret[#ret + 1] = { " " }
      Snacks.picker.highlight.extend(ret, Snacks.picker.format.git_log(item, picker))
      return ret
    end,
    -- preview = "none",
    preview = "git_log",
    layout = {
      preview = true,
    },
    formatters = {
      file = {
        truncate = "center",
        -- min_width = 40,
        icon_width = 2,
      },
    },
    confirm = switch_worktree,
    actions = {
      add_new_branch_and_worktree = add_new_branch_and_worktree,
      add_new_detached_head_worktree = add_new_detached_head_worktree,
      delete_worktree = delete_worktree,
      toggle_forced_deletion = toggle_forced_deletion,
    },
    win = {
      input = {
        keys = {
          ["<c-x>"] = { "delete_worktree", mode = { "n", "i" } },
          ["<c-f>"] = { "toggle_forced_deletion", mode = { "n", "i" } },
          ["<c-a>"] = { "add_new_branch_and_worktree", mode = { "n", "i" } },
          ["<c-d>"] = { "add_new_detached_head_worktree", mode = { "n", "i" } },
        },
      },
    },
    ---@param picker snacks.Picker
    on_show = function(picker)
      for i, item in ipairs(picker:items()) do
        if item.current then
          picker.list:view(i)
          Snacks.picker.actions.list_scroll_center(picker)
          break
        end
      end
    end,
  })
end, { desc = "Manage git worktrees" })

--------------------------------------------------------------------------------
-- user command
--------------------------------------------------------------------------------

-- local subcommands = { "create", "switch", "delete" }
--
-- local function get_git_remotes()
--   local branches = vim.fn.systemlist("git remote")
--   return vim.tbl_filter(function(b)
--     return b ~= ""
--   end, branches)
-- end
--
--
-- vim.api.nvim_create_user_command("Worktree", function(args)
--   local fargs = args.fargs
--   local cmd = fargs[1]
--
--   if not cmd then
--     print("Available: " .. table.concat(subcommands, ", "))
--     return
--   end
--
--   if cmd == "create" then
--     -- worktree.create_worktree(path, branch, upstream?)
--     return worktree.create_worktree(fargs[2], fargs[3], fargs[4])
--   elseif cmd == "switch" then
--     -- use fargs[2]
--     return worktree.switch_worktree(fargs[2])
--   elseif cmd == "delete" then
--     return worktree.delete_worktree(fargs[2], fargs[3] == "true")
--   end
-- end, {
--   nargs = "+", -- Changed to + to easily capture subcommand + args
--   complete = function(ArgLead, CmdLine, CursorPos)
--     -- Split the command line by whitespace
--     -- Example: "Worktree create " -> {"Worktree", "create", ""}
--     local parts = vim.split(CmdLine, "%s+")
--     local n = #parts
--
--     -- If we are at the second part, we are completing the subcommand itself
--     -- Note: if CmdLine is "Worktree ", parts is {"Worktree", ""}
--     if n <= 2 then
--       return vim.tbl_filter(function(item)
--         return item:find(ArgLead, 1, true)
--       end, subcommands)
--     end
--
--     -- If we are at the third part or beyond, we look at the subcommand
--     local subcommand = parts[2]
--
--     if subcommand == "create" then
--       if n == 3 then
--         return { ".worktrees" }
--       elseif n == 4 then
--         return vim.tbl_filter(function(b)
--           return b:find(ArgLead, 1, true)
--         end, get_git_branches())
--       end
--       return vim.tbl_filter(function(p)
--         return p:find(ArgLead, 1, true)
--       end, get_git_remotes())
--     elseif subcommand == "switch" then
--       return vim.tbl_filter(function(p)
--         return p:find(ArgLead, 1, true)
--       end, get_worktree_paths())
--     elseif subcommand == "delete" then
--       if n == 3 then
--         return vim.tbl_filter(function(p)
--           return p:find(ArgLead, 1, true)
--         end, get_worktree_paths())
--       end
--
--       return { "true", "false" }
--     end
--   end,
-- })

return {}
