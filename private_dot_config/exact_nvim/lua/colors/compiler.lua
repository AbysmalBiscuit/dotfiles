local M = {}

---Flatten a theme
---@param theme Theme
---@return HighlightGroupTable
M.flatten_theme = function(theme)
  local flat_table = {}

  if theme.editor then
    flat_table = vim.tbl_deep_extend("force", flat_table, theme.editor)
    -- for name, group in pairs(theme.editor) do
    --   flat_table[name] = group
    -- end
  end

  if theme.syntax then
    flat_table = vim.tbl_deep_extend("force", flat_table, theme.syntax)
    -- for _, group in pairs(theme.syntax) do
    --   flat_table[name] = vim.tbl_deep_extend("force", flat_table, group)
    -- end
  end

  if theme.integrations then
    for name, integration in pairs(theme.integrations) do
      if name == "treesitter" then
        for _, treesitter_integration in pairs(integration) do
          flat_table = vim.tbl_deep_extend("force", flat_table, treesitter_integration)
        end
      else
        flat_table = vim.tbl_deep_extend("force", flat_table, integration)
      end
      -- for _, group in pairs(integration) do
      --   flat_table = vim.tbl_deep_extend("force", flat_table, group)
      -- end
    end
  end

  return flat_table
end

-- Utility function to format tables as strings
local function inspect(t)
  local list = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "string" then
      table.insert(list, string.format([[%s = "%s"]], k, v))
    elseif tv == "table" then
      table.insert(list, string.format([[%s = %s]], k, inspect(v)))
    else
      table.insert(list, string.format([[%s = %s]], k, tostring(v)))
    end
  end
  return string.format([[{ %s }]], table.concat(list, ", "))
end

-- Convert exclude config into a set for fast lookup
local function to_set(list)
  local set = {}
  if type(list) == "table" then
    for k, v in pairs(list) do
      if type(k) == "string" then
        set[k] = true
      elseif type(v) == "string" then
        set[v] = true
      end
    end
  end
  return set
end

--- Main function to compile a colorscheme
---@param config CompileConfig
function M.compile(config)
  local theme = config.theme
  local background = config.background or "dark"
  local flavor = config.flavor or "default"
  local compile_path = config.compile_path or vim.fn.stdpath("cache") .. "/compiled_colorscheme/abc"
  local term_colors = config.term_colors or false
  local no_italic = config.no_italic or false
  local no_bold = config.no_bold or false
  local no_underline = config.no_underline or false
  local exclude_set = to_set(config.exclude or {})
  local debug_ = config.debug or false

  -- Adjust header based on merge
  local lines = {
    string.format(
      [[
return string.dump(function(merge)
vim.o.termguicolors = true
if not merge then
vim.g.colors_name = "%s"
vim.cmd("hi clear")
end
vim.o.background = "%s"
local h = vim.api.nvim_set_hl]],
      flavor,
      background
    ),
  }

  local tbl = vim.tbl_deep_extend("force", theme.syntax or {}, theme.editor or {}, theme.custom or {})

  if theme.integrations then
    for name, integration in pairs(theme.integrations) do
      if name == "treesitter" or name == "treesitter_languages" then
        for _, treesitter_integration in pairs(integration) do
          tbl = vim.tbl_deep_extend("force", tbl, treesitter_integration)
        end
      else
        tbl = vim.tbl_deep_extend("force", tbl, integration)
      end
    end
  end

  if term_colors then
    -- if theme.terminal then
    for k, v in pairs(theme.terminal or {}) do
      table.insert(lines, string.format('vim.g.%s = "%s"', k, v))
    end
  end

  for group, color in pairs(tbl) do
    if not exclude_set[group] then
      if color.style then
        for _, style in ipairs(color.style) do
          if string.sub(style, 1, 2) == "no" then
            color[string.sub(style, 3, -1)] = false
            color["force"] = true
            color["default"] = true
          else
            color[style] = true
            if no_italic and style == "italic" then
              color[style] = false
            end
            if no_bold and style == "bold" then
              color[style] = false
            end
            if no_underline and style == "underline" then
              color[style] = false
            end
          end
        end
      end
      color.style = nil
      if color.link then
        table.insert(lines, string.format([[h(0, "%s", { link = "%s" })]], group, color.link))
      else
        table.insert(lines, string.format([[h(0, "%s", %s)]], group, inspect(color)))
      end
    end
  end
  table.insert(lines, "end, true)")

  local path_sep = "/"

  ---@type string[]
  local compile_path_split = vim.split(compile_path, "/")
  ---@type string
  compile_path = table.concat(vim.list_slice(compile_path_split, 1, #compile_path_split - 1), "/")

  if vim.fn.has("win32") == 1 then
    compile_path = compile_path:gsub("/", "\\")
    path_sep = "\\"
  end

  if vim.fn.isdirectory(compile_path) == 0 then
    vim.fn.mkdir(compile_path, "p")
  end

  local file_path = compile_path .. path_sep .. flavor
  local file_path_lua = file_path .. ".lua"

  local f = loadstring(table.concat(lines, "\n"))
  if not f then
    vim.notify(
      string.format(
        "Failed to load theme as binary content in preparation for writing binary blob. Check the lua version of the theme '%s'",
        file_path_lua
      ),
      vim.log.levels.ERROR
    )
    debug_ = true
  end

  if debug_ then
    vim.notify("saving abc debug theme version")
    local file =
      assert(io.open(file_path_lua, "wb"), "Permission denied while writing compiled theme lua file to: " .. file_path)
    file:write(table.concat(lines, "\n"))
    file:close()
  end

  if f then
    vim.notify("writing binary file: " .. file_path)
    local file = assert(
      io.open(file_path, "wb"),
      string.format("Permission denied to write the compiled theme to: '%s'", file_path)
    )

    file:write(f())
    file:close()
  end

  return file_path, lines, exclude_set
end

return M
