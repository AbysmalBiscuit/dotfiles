local M = {}

local function get_commentstring()
  local cs = vim.bo.commentstring
  if not cs or cs == "" then
    cs = "// %s"
  end
  local left, right = cs:match("^(.-)%%s(.-)$")
  return vim.trim(left or "//"), vim.trim(right or "")
end

---@param line string Text line to search
local function find_tmpl_ranges(line)
  local ranges = {}
  local pos = 1
  while pos <= #line do
    local s = line:find("{{", pos, true)
    if not s then
      break
    end
    local rest = line:sub(s)
    local full = rest:match("^({{-?%s*/%*.-%*/%s*-?}})")
    if full then
      table.insert(ranges, { start = s, stop = s + #full - 1, commented = true })
      pos = s + #full
    else
      local ee = line:find("}}", s + 2, true)
      if ee then
        table.insert(ranges, { start = s, stop = ee + 1, commented = false })
        pos = ee + 2
      else
        pos = s + 2
      end
    end
  end
  return ranges
end

local function range_at_col(ranges, col)
  for _, r in ipairs(ranges) do
    if col >= r.start and col <= r.stop then
      return r
    end
  end
  return nil
end

-- Check if all non-whitespace on a line falls within {{ }} ranges
local function is_tmpl_only_line(line)
  local ranges = find_tmpl_ranges(line)
  if #ranges == 0 then
    return false, ranges
  end
  for i = 1, #line do
    if line:sub(i, i):match("%S") then
      local inside = false
      for _, r in ipairs(ranges) do
        if i >= r.start and i <= r.stop then
          inside = true
          break
        end
      end
      if not inside then
        return false, ranges
      end
    end
  end
  return true, ranges
end

local function toggle_tmpl_expr(line, range)
  local prefix = line:sub(1, range.start - 1)
  local tmpl = line:sub(range.start, range.stop)
  local suffix = line:sub(range.stop + 1)

  if range.commented then
    local ldash, inner, rdash = tmpl:match("^{{(-?)%s*/%*%s?(.-)%s?%*/%s*(-?)}}$")
    if inner then
      if ldash == "" and rdash == "" then
        return prefix .. "{{ " .. inner .. " }}" .. suffix
      end
      return prefix .. "{{" .. ldash .. " " .. inner .. " " .. rdash .. "}}" .. suffix
    end
  else
    local ldash, inner, rdash = tmpl:match("^{{(-?)%s?(.-)%s?(-?)}}$")
    if inner then
      if ldash == "" and rdash == "" then
        return prefix .. "{{/* " .. inner .. " */}}" .. suffix
      end
      ldash = (ldash ~= "") and ldash .. " " or ""
      rdash = (rdash ~= "") and " " .. rdash or ""
      return prefix .. "{{" .. ldash .. "/* " .. inner .. " */" .. rdash .. "}}" .. suffix
    end
  end
  return line
end

--- Toggle all tmpl expressions on a range of tmpl-only lines
local function toggle_tmpl_lines(line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  local all_ranges = {}
  for i, l in ipairs(lines) do
    all_ranges[i] = find_tmpl_ranges(l)
  end

  local should_comment = false
  for _, ranges in ipairs(all_ranges) do
    for _, r in ipairs(ranges) do
      if not r.commented then
        should_comment = true
        break
      end
    end
    if should_comment then
      break
    end
  end

  local new = {}
  for i, l in ipairs(lines) do
    local result = l
    for j = #all_ranges[i], 1, -1 do
      local r = all_ranges[i][j]
      if should_comment == not r.commented then
        result = toggle_tmpl_expr(result, r)
      end
    end
    table.insert(new, result)
  end
  vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, new)
end

------------------ Normal line commenting ------------------

local function is_line_commented(line, cs_left)
  return line:match("^%s*" .. vim.pesc(cs_left)) ~= nil
end

local function comment_line(line, cs_left, cs_right)
  local indent, content = line:match("^(%s*)(.*)")
  if content == "" then
    return line
  end
  if cs_right ~= "" then
    return indent .. cs_left .. " " .. content .. " " .. cs_right
  end
  return indent .. cs_left .. " " .. content
end

local function uncomment_line(line, cs_left, cs_right)
  local left = vim.pesc(cs_left)
  local right = vim.pesc(cs_right)
  local pattern = right ~= "" and ("^(%s*)" .. left .. "%s?(.-)" .. "%s?" .. right .. "$")
    or ("^(%s*)" .. left .. "%s?(.*)")
  local indent, inner = line:match(pattern)
  if indent and inner then
    return indent .. inner
  end
  return line
end

local function toggle_lines_normal(line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  local cs_left, cs_right = get_commentstring()

  local should_comment = false
  for _, l in ipairs(lines) do
    if l:match("%S") and not is_line_commented(l, cs_left) then
      should_comment = true
      break
    end
  end

  local new = {}
  for _, l in ipairs(lines) do
    if not l:match("%S") then
      table.insert(new, l)
    elseif should_comment then
      table.insert(new, comment_line(l, cs_left, cs_right))
    else
      table.insert(new, uncomment_line(l, cs_left, cs_right))
    end
  end
  vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, new)
end

--- Smart toggle: if ALL non-blank lines are tmpl-only, use tmpl commenting; else normal
local function toggle_lines_smart(line1, line2)
  local all_tmpl = true
  for lnum = line1, line2 do
    local line = vim.fn.getline(lnum)
    if line:match("%S") and not is_tmpl_only_line(line) then
      all_tmpl = false
      break
    end
  end

  if all_tmpl then
    toggle_tmpl_lines(line1, line2)
  else
    toggle_lines_normal(line1, line2)
  end
end

------------------ Selection helpers ------------------

local function selection_in_tmpl(start_line, end_line, start_col, end_col)
  local tmpl_hits = {}

  for lnum = start_line, end_line do
    local line = vim.fn.getline(lnum)
    if not line:match("%S") then
      goto continue
    end

    local col_lo, col_hi
    if start_line == end_line then
      col_lo, col_hi = start_col, end_col
    elseif lnum == start_line then
      col_lo, col_hi = start_col, #line
    elseif lnum == end_line then
      col_lo, col_hi = 1, end_col
    else
      col_lo, col_hi = 1, #line
    end

    local ranges = find_tmpl_ranges(line)
    local r1 = range_at_col(ranges, col_lo)
    local r2 = range_at_col(ranges, col_hi)
    if r1 and r2 and r1.start == r2.start then
      table.insert(tmpl_hits, { lnum = lnum, range = r1 })
    else
      return nil
    end
    ::continue::
  end

  return tmpl_hits
end

local function toggle_tmpl_hits(tmpl_hits)
  local should_comment = false
  for _, h in ipairs(tmpl_hits) do
    if not h.range.commented then
      should_comment = true
      break
    end
  end
  for i = #tmpl_hits, 1, -1 do
    local h = tmpl_hits[i]
    if should_comment == not h.range.commented then
      local line = vim.fn.getline(h.lnum)
      vim.fn.setline(h.lnum, toggle_tmpl_expr(line, h.range))
    end
  end
end

------------------ Operator callbacks ------------------

-- gcc: cursor-aware (inside {{ }} → tmpl, outside → normal)
function M.op_gcc(_type)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  col = col + 1
  local line = vim.api.nvim_get_current_line()

  local tmpl_only = is_tmpl_only_line(line)
  if tmpl_only then
    toggle_tmpl_lines(row, row)
    return
  end

  local ranges = find_tmpl_ranges(line)
  local range = range_at_col(ranges, col)
  if range then
    vim.api.nvim_set_current_line(toggle_tmpl_expr(line, range))
  else
    toggle_lines_normal(row, row)
  end
end

-- gc{motion}: smart linewise toggle
function M.op_motion(_type)
  local start = vim.api.nvim_buf_get_mark(0, "[")[1]
  local stop = vim.api.nvim_buf_get_mark(0, "]")[1]
  toggle_lines_smart(start, stop)
end

-- visual gc: charwise/blockwise checks columns, linewise uses smart toggle
function M.op_visual(type)
  local start_line = vim.api.nvim_buf_get_mark(0, "[")[1]
  local end_line = vim.api.nvim_buf_get_mark(0, "]")[1]

  if type == "char" or type == "block" then
    local start_col = vim.api.nvim_buf_get_mark(0, "[")[2] + 1
    local end_col = vim.api.nvim_buf_get_mark(0, "]")[2] + 1
    local tmpl_hits = selection_in_tmpl(start_line, end_line, start_col, end_col)
    if tmpl_hits and #tmpl_hits > 0 then
      toggle_tmpl_hits(tmpl_hits)
      return
    end
  end

  toggle_lines_smart(start_line, end_line)
end

------------------ Setup keymaps ------------------

function M.setup(opts)
  opts = opts or {}
  local map_opts = { buffer = true, silent = true }

  -- gcc → g@_ (current line motion, dot-repeatable)
  vim.keymap.set("n", "gcc", function()
    vim.go.operatorfunc = "v:lua.require'gotmpl_comment'.op_gcc"
    return "g@_"
  end, vim.tbl_extend("force", map_opts, { expr = true }))

  -- gc{motion} → g@ (user supplies motion, dot-repeatable)
  vim.keymap.set("n", "gc", function()
    vim.go.operatorfunc = "v:lua.require'gotmpl_comment'.op_motion"
    return "g@"
  end, vim.tbl_extend("force", map_opts, { expr = true }))

  -- visual gc → g@ from visual mode (dot repeats over same line count)
  vim.keymap.set("x", "gc", function()
    vim.go.operatorfunc = "v:lua.require'gotmpl_comment'.op_visual"
    return "g@"
  end, vim.tbl_extend("force", map_opts, { expr = true }))
end

return M
