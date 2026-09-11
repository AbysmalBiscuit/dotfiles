local M = {}

function M.closing_line(lines)
  if not lines[1] or not lines[1]:match("^%-%-%-%s*$") then
    return
  end
  for i = 2, #lines do
    if lines[i]:match("^%-%-%-%s*$") then
      return i
    end
  end
  return #lines + 1
end

---Wrapper to call yq
---@param input any
---@param expression any
---@param format any
---@param env any
---@return string?
local function yq(input, expression, format, env)
  local result = vim
    .system({ "yq", "eval", "-p=yaml", "-o=" .. format, expression, "-" }, {
      stdin = input,
      text = true,
      env = env,
    })
    :wait(2000)

  assert(result.code == 0, vim.trim(result.stderr or "yq failed"))

  return result.stdout
end

local function mapping(value, location)
  assert(type(value) == "table" and not vim.islist(value), location .. " must be a YAML map")
  return value
end

local function single_line(value, location)
  assert(type(value) == "string" and vim.trim(value) ~= "", location .. " must be a nonempty string")
  return vim.trim(value:gsub("%s+", " "))
end

function M.sync(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if vim.fs.basename(path) ~= "SKILL.md" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local closing = M.closing_line(lines)
  if not closing then
    return
  end

  assert(closing <= #lines, "SKILL.md frontmatter needs a closing ---")
  assert(vim.fn.executable("yq") == 1, "install Mike Farah's yq v4 to sync agents/openai.yaml")

  local frontmatter = table.concat(vim.list_slice(lines, 2, closing - 1), "\n")
  local data = mapping(vim.json.decode(yq(frontmatter, ".", "json")), "SKILL.md frontmatter")
  local directory = vim.fs.dirname(vim.uv.fs_realpath(path) or path)
  local name = single_line(data.name or vim.fs.basename(directory), "name")

  assert(vim.fn.strchars(name) <= 64, "name must fit Codex's 64-character limit")

  local description = single_line(data.description, "description")
  local metadata = data.metadata and mapping(data.metadata, "metadata") or {}
  local short = single_line(metadata["short-description"] or description, "short-description")
  short = vim.fn.strcharpart(short, 0, 64)
  local disabled = data["disable-model-invocation"]

  if disabled == nil then
    disabled = false
  elseif type(disabled) ~= "boolean" then
    local booleans = {
      ["true"] = true,
      yes = true,
      on = true,
      ["1"] = true,
      ["false"] = false,
      no = false,
      off = false,
      ["0"] = false,
    }
    disabled = booleans[tostring(disabled):lower()]
    assert(disabled ~= nil, "disable-model-invocation must be a boolean")
  end

  local target = vim.fs.joinpath(directory, "agents", "openai.yaml")
  local target_buf = vim.fn.bufnr(target)
  assert(target_buf == -1 or not vim.bo[target_buf].modified, "agents/openai.yaml has unsaved edits; save it first")

  local original = vim.uv.fs_stat(target) and table.concat(vim.fn.readfile(target, "b"), "\n") or ""
  if original ~= "" then
    local existing = mapping(vim.json.decode(yq(original, ".", "json")), "agents/openai.yaml")
    for _, key in ipairs({ "interface", "policy" }) do
      if existing[key] ~= nil then
        mapping(existing[key], "agents/openai.yaml " .. key)
      end
    end
  end

  local updated = yq(
    original == "" and "{}" or original,
    table.concat({
      ".interface.display_name = strenv(SKILL_DISPLAY_NAME)",
      ".interface.short_description = strenv(SKILL_SHORT_DESCRIPTION)",
      ".policy.allow_implicit_invocation = env(SKILL_ALLOW_IMPLICIT)",
    }, " | "),
    "yaml",
    {
      SKILL_DISPLAY_NAME = name,
      SKILL_SHORT_DESCRIPTION = short,
      SKILL_ALLOW_IMPLICIT = tostring(not disabled),
    }
  )

  if updated == original then
    return
  end

  vim.fn.mkdir(vim.fs.dirname(target), "p")
  assert(vim.fn.writefile(vim.split(updated, "\n", { plain = true }), target, "b") == 0, "cannot write " .. target)
  if target_buf ~= -1 then
    vim.cmd("checktime " .. target_buf)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("SkillFrontmatter", { clear = true }),
    pattern = "SKILL.md",
    desc = "Sync skill metadata and invocation policy to agents/openai.yaml",
    callback = function(args)
      local ok, err = pcall(M.sync, args.buf)
      if not ok then
        vim.notify(args.file .. ": " .. tostring(err), vim.log.levels.WARN, { title = "Skill frontmatter sync" })
      end
    end,
  })
end

return M
