vim.notify("gdscript ftplugin loaded")
local ts_indent = require("nvim-treesitter.indent")

vim.opt_local.expandtab = false
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.softtabstop = 0

vim.opt_local.indentexpr = "v:lua.GDScriptIndent()"
vim.opt_local.foldexpr = "v:lua.GDScriptFoldExpr()"
vim.opt_local.foldmethod = "expr"

local function offset_ts_level(ts_val, offset)
  ts_val = tostring(ts_val)
  -- handles ">1", "<1", "1", "0"
  local prefix, num = ts_val:match("^([><]?)(%d+)$")
  if num then
    return prefix .. (tonumber(num) + offset)
  end
  return ts_val
end

function _G.GDScriptFoldExpr()
  local lnum = vim.v.lnum
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""

  if line:match("^%s*#region") then
    return ">1"
  elseif line:match("^%s*#endregion") then
    return "<1"
  end

  local ts_val = vim.treesitter.foldexpr()

  for i = lnum - 1, 1, -1 do
    local l = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1] or ""
    if l:match("^%s*#region") then
      return offset_ts_level(ts_val, 1)
    elseif l:match("^%s*#endregion") then
      break
    end
  end

  return ts_val
end

function _G.GDScriptIndent()
  local lnum = vim.v.lnum
  local prev_lnum = vim.fn.prevnonblank(lnum - 1)
  if prev_lnum == 0 then
    return 0
  end

  local prev_line = vim.api.nvim_buf_get_lines(0, prev_lnum - 1, prev_lnum, false)[1] or ""

  -- Only bother if the previous line ends with ':'
  if prev_line:match(":%s*$") then
    local col = (prev_line:find(":%s*$") or 1) - 1
    local node = vim.treesitter.get_node({ pos = { prev_lnum - 1, col }, bufnr = 0 })

    while node do
      local ntype = node:type()
      if
        ntype == "lambda"
        or ntype == "function_definition"
        or ntype == "constructor_definition"
        or ntype == "for_statement"
        or ntype == "while_statement"
        or ntype == "if_statement"
        or ntype == "class_definition"
      then
        local _, _, end_row, _ = node:range() -- 0-indexed
        -- If node ends on the same line, body is empty → indent in
        if end_row == prev_lnum - 1 then
          vim.notify(vim.fn.indent(prev_lnum) + vim.fn.shiftwidth())
          return vim.fn.indent(prev_lnum) + vim.fn.shiftwidth()
        end
        break
      end
      node = node:parent()
    end
  end

  return ts_indent.get_indent(lnum)
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "gdscript", -- match whatever :set filetype? returns
  callback = function()
    vim.schedule(function()
      vim.opt_local.indentexpr = "v:lua.GDScriptIndent()"
      vim.opt_local.foldexpr = "v:lua.GDScriptFoldExpr()"
      vim.opt_local.foldmethod = "expr"
      vim.opt_local.expandtab = false
      vim.opt_local.shiftwidth = 4
      vim.opt_local.tabstop = 4
      vim.opt_local.softtabstop = 0
      vim.opt_local.foldlevel = 99
      vim.opt_local.foldlevelstart = 99
    end)
  end,
})
