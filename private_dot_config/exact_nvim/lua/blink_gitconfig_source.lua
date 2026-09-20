local kinds = require("blink.cmp.types").CompletionItemKind

local source = {}

local cache = {}
local pending = {}

--- Run `cmd` once per session and hand every caller the parsed result.
---@param name string
---@param cmd string[]
---@param parse fun(stdout: string): table
---@param cb fun(value: table)
local function cached(name, cmd, parse, cb)
  if cache[name] then
    return cb(cache[name])
  end

  local queue = pending[name]
  if queue then
    queue[#queue + 1] = cb
    return
  end
  pending[name] = { cb }

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      cache[name] = parse(obj.stdout or "")
      local waiting = pending[name] or {}
      pending[name] = nil
      for _, fn in ipairs(waiting) do
        fn(cache[name])
      end
    end)
  end)
end

--- `git help --config` prints one key per line, with `<name>` standing in for a
--- subsection and `*` for an arbitrary leaf. Keep the placeholder-free leaves and
--- record whether each one is reachable with a subsection, without one, or both.
local function parse_config_keys(stdout)
  local sections, section_order, seen_section = {}, {}, {}

  for line in stdout:gmatch("[^\r\n]+") do
    local name, rest = line:match("^([%w%-]+)%.(.+)$")
    if name then
      local key = name:lower()
      if not seen_section[key] then
        seen_section[key] = true
        section_order[#section_order + 1] = name
      end

      local subsection_leaf = rest:match("^<[^>]+>%.(.+)$")
      local leaf = subsection_leaf or rest
      if not leaf:find("[<>*]") then
        local entries = sections[key] or { order = {}, by_leaf = {} }
        sections[key] = entries

        local entry = entries.by_leaf[leaf]
        if not entry then
          entry = { leaf = leaf }
          entries.by_leaf[leaf] = entry
          entries.order[#entries.order + 1] = entry
        end
        if subsection_leaf then
          entry.sub = line
        else
          entry.plain = line
        end
      end
    end
  end

  return { sections = sections, section_names = section_order }
end

local function parse_lines(stdout)
  local list = {}
  for line in stdout:gmatch("[^\r\n]+") do
    list[#list + 1] = line
  end
  return list
end

local function config_keys(cb)
  cached("config", { "git", "help", "--config" }, parse_config_keys, cb)
end

local function git_commands(cb)
  cached("commands", { "git", "--list-cmds=list-mainporcelain,others,nohelpers" }, parse_lines, cb)
end

--- Walk back from the cursor for the section header that governs this line.
---@return string? section, boolean has_subsection
local function enclosing_section(ctx)
  local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, ctx.cursor[1] - 1, false)
  for i = #lines, 1, -1 do
    local header = lines[i]:match("^%s*%[([^%]]+)%]")
    if header then
      local name = header:match("^%s*([%w%-]+)")
      if not name then
        return nil, false
      end
      local has_subsection = header:find('"') ~= nil or header:find("^%s*[%w%-]+%.") ~= nil
      return name:lower(), has_subsection
    end
  end
  return nil, false
end

local function word_start(line, col, pattern)
  local start = col
  while start > 0 and line:sub(start, start):match(pattern) do
    start = start - 1
  end
  return start
end

function source.new(opts)
  return setmetatable({ opts = opts or {} }, { __index = source })
end

function source:enabled()
  return vim.bo.filetype:match("^gitconfig") ~= nil
end

function source:get_trigger_characters()
  return { "[", "=" }
end

function source:get_completions(ctx, callback)
  local line = ctx.line
  local col = ctx.cursor[2]
  local row = ctx.cursor[1] - 1
  local before = line:sub(1, col)

  local cancelled = false
  local function respond(items)
    if not cancelled then
      callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
    end
  end

  local function build(labels, kind, detail_of, start_col, suffix)
    local items = {}
    for _, label in ipairs(labels) do
      local text = label .. (suffix or "")
      items[#items + 1] = {
        label = label,
        kind = kind,
        detail = detail_of and detail_of(label) or nil,
        filterText = label,
        textEdit = {
          newText = text,
          range = {
            start = { line = row, character = start_col },
            ["end"] = { line = row, character = col },
          },
        },
      }
    end
    return items
  end

  if before:match("^%s*%[%s*[%w%-]*$") then
    config_keys(function(data)
      local start_col = word_start(before, col, "[%w%-]")
      local suffix = line:sub(col + 1, col + 1) == "]" and "" or "]"
      respond(build(data.section_names, kinds.Module, nil, start_col, suffix))
    end)
    return function()
      cancelled = true
    end
  end

  local section, has_subsection = enclosing_section(ctx)
  if not section then
    respond({})
    return function() end
  end

  if before:match("^%s*[%w%-]+%s*=%s*[^%s]*$") then
    if section ~= "alias" then
      respond({})
      return function() end
    end
    git_commands(function(commands)
      respond(build(commands, kinds.Value, nil, word_start(before, col, "[%w%-]"), nil))
    end)
    return function()
      cancelled = true
    end
  end

  if not before:match("^%s*[%w%-]*$") then
    respond({})
    return function() end
  end

  config_keys(function(data)
    local entries = data.sections[section]
    if not entries then
      return respond({})
    end

    local labels, details = {}, {}
    for _, entry in ipairs(entries.order) do
      local full = has_subsection and entry.sub or (not has_subsection and entry.plain)
      if full then
        labels[#labels + 1] = entry.leaf
        details[entry.leaf] = full
      end
    end

    respond(build(labels, kinds.Property, function(label)
      return details[label]
    end, word_start(before, col, "[%w%-]"), nil))
  end)

  return function()
    cancelled = true
  end
end

vim.api.nvim_create_user_command("RefreshGitconfigKeys", function()
  cache.config = nil
  cache.commands = nil
end, {})

return source
