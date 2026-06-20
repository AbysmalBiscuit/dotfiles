local cache = require("exe_cache")

local source = {}

function source.new(opts)
  return setmetatable({ opts = opts or {} }, { __index = source })
end

function source:enabled()
  if vim.fn.getcmdtype() ~= ":" then
    return false
  end
  return vim.fn.getcmdline():match("^%s*[%%%d,%.%$'<>]*!") ~= nil
end

function source:get_completions(ctx, callback)
  -- find the start of the "word" under/after the cursor on the cmdline.
  -- ctx.cursor is { row, col } with col 0-indexed-ish; use the line text.
  local line = ctx.line or vim.fn.getcmdline()
  local col = ctx.cursor[2] or #line -- character index of cursor

  -- walk back from cursor over executable-name chars to find word start
  local start = col
  while start > 0 do
    local ch = line:sub(start, start)
    if ch:match("[%w%._%-]") then
      start = start - 1
    else
      break
    end
  end
  -- `start` is now just before the word; word begins at start+1 (1-indexed)
  local word_start_char = start -- 0-indexed for LSP range

  local keyword = line:sub(start + 1, col)

  local items = {}
  for _, it in ipairs(require("exe_cache").items) do
    items[#items + 1] = {
      label = it.label,
      kind = it.kind,
      textEdit = {
        newText = it.label,
        range = {
          start = { line = 0, character = word_start_char },
          ["end"] = { line = 0, character = col },
        },
      },
      filterText = it.label,
    }
  end

  callback({
    items = items,
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  })
  return function() end
end

return source
