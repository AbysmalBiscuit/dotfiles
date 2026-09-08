local fields = require("skill_frontmatter.fields")
local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "SKILL.md"
end

function source:get_completions(ctx, callback)
  local items = {}
  local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
  local row, col = unpack(ctx.cursor)
  local closing = require("skill_frontmatter").closing_line(lines)
  if vim.fs.basename(vim.api.nvim_buf_get_name(ctx.bufnr)) == "SKILL.md" and closing and row > 1 and row < closing then
    local line = lines[row]
    local prefix = line:sub(1, col)
    local indent, key = prefix:match("^( *)([%w_-]*)$")
    local value_key, value_prefix = prefix:match("^([%w_-]+):%s*([%w_-]*)$")
    local parent
    if indent and #indent > 0 then
      for i = row - 1, 2, -1 do
        if lines[i]:match("^%S") and not lines[i]:match("^#") then
          parent = lines[i]:match("^([%w_-]+):%s*$")
          break
        end
      end
    end
    for _, field in ipairs(fields) do
      local candidates, start_col, end_col
      if key and field.parent == parent and (#indent == 0 or parent) then
        local exists = false
        local section
        for i = 2, math.min(closing - 1, #lines) do
          local top_key = lines[i]:match("^([%w_-]+):")
          if top_key then
            section = top_key
          end
          local existing_key = field.parent and section == field.parent and lines[i]:match("^ +([%w_-]+):")
            or (not field.parent and top_key)
          if i ~= row and existing_key == field.name then
            exists = true
          end
        end
        if not exists then
          end_col = #indent + #(line:sub(#indent + 1):match("^[%w_-]*"))
          candidates = { field.name .. (line:sub(end_col + 1):match("^%s*:") and "" or ": ") }
          start_col = #indent
        end
      elseif value_key == field.name and not field.parent and field.values then
        candidates = field.values
        start_col = col - #value_prefix
        end_col = col + #(line:sub(col + 1):match("^[%w_-]*"))
      end
      for _, text in ipairs(candidates or {}) do
        items[#items + 1] = {
          label = key and field.name or text,
          labelDetails = { description = "[" .. table.concat(field.harnesses, ", ") .. "]" },
          kind = key and vim.lsp.protocol.CompletionItemKind.Property or vim.lsp.protocol.CompletionItemKind.Value,
          documentation = { kind = "markdown", value = "`" .. field.name .. "`\n\n" .. field.description },
          textEdit = {
            newText = text,
            range = {
              start = { line = row - 1, character = start_col },
              ["end"] = { line = row - 1, character = end_col },
            },
          },
        }
      end
    end
  end
  callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
end

function source:get_trigger_characters()
  return { ":", " " }
end

return source
