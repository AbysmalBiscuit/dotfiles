-- Run with: nvim --headless -u NONE -l /path/to/nvim/tests/skill_frontmatter.lua
local config = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.runtimepath:prepend(config)
local plugin = require("plugins.skills")[1]
plugin.init()
plugin.init()
assert(#vim.api.nvim_get_autocmds({ group = "SkillFrontmatter" }) == 1)
local opts = { sources = { default = {}, providers = {} } }
plugin.opts(nil, opts)
assert(opts.sources.default[1] == "skill_frontmatter")
local source = require(opts.sources.providers.skill_frontmatter.module).new()
local directory = vim.fn.tempname() .. " skill's directory"
vim.fn.mkdir(directory, "p")
vim.cmd.edit(vim.fn.fnameescape(directory .. "/SKILL.md"))
local buf = vim.api.nvim_get_current_buf()
local notifications = {}
vim.notify = function(message)
  notifications[#notifications + 1] = message
end

local function complete(lines, row, col)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local items
  source:get_completions({ bufnr = buf, cursor = { row, col } }, function(result)
    items = result.items
  end)
  assert(items)
  return items
end

local function item_named(items, name)
  for _, item in ipairs(items) do
    if item.label == name then
      return item
    end
  end
end

local items = complete({ "---", "dis", "---", "Body" }, 2, 3)
local disable = assert(item_named(items, "disable-model-invocation"))
assert(disable.labelDetails.description == "[Claude]")
assert(item_named(items, "name").labelDetails.description == "[Claude, Codex]")
assert(disable.documentation.value:find("allow_implicit_invocation", 1, true))
vim.lsp.util.apply_text_edits({ disable.textEdit }, buf, "utf-8")
assert(vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "disable-model-invocation: ")
for _, field in ipairs(require("skill_frontmatter.fields")) do
  if not field.parent then
    assert(item_named(items, field.name), field.name .. " missing")
  end
end
items = complete({ "---", "name: example", "na", "---" }, 3, 2)
assert(not item_named(items, "name"))
items = complete({ "---", "disable-model-invocation: tr # note", "---" }, 2, 26)
vim.lsp.util.apply_text_edits({ assert(item_named(items, "true")).textEdit }, buf, "utf-8")
assert(vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "disable-model-invocation: true # note")
items = complete({ "---", "dis: false", "---" }, 2, 3)
vim.lsp.util.apply_text_edits({ assert(item_named(items, "disable-model-invocation")).textEdit }, buf, "utf-8")
assert(vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "disable-model-invocation: false")
items = complete({ "---", "metadata:", "  sh", "---" }, 3, 4)
assert(#items == 1 and items[1].labelDetails.description == "[Codex]")
assert(#complete({ "---", "description: |", "  so", "---" }, 3, 4) == 0)
assert(#complete({ "---", "name: example", "---", "dis" }, 4, 3) == 0)
assert(#complete({ "Body", "---", "dis" }, 3, 3) == 0)
assert(item_named(complete({ "---", "dis" }, 2, 3), "disable-model-invocation"))

local target = directory .. "/agents/openai.yaml"
local function save(lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd.write()
end
local function read()
  local result = vim.system({ "yq", "-o=json", ".", target }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.json.decode(result.stdout)
end
local frontmatter = {
  "---",
  'name: "Skill: example"',
  "description: >-",
  "  Description with a colon: and",
  "  another line.",
  "metadata:",
  "  short-description: 'A concise summary for the skill'",
  "disable-model-invocation: true",
  "---",
  "# Body",
}
save(frontmatter)
assert(#notifications == 0, vim.inspect(notifications))
local generated = read()
assert(generated.interface.display_name == "Skill: example")
assert(generated.interface.short_description == "A concise summary for the skill")
assert(generated.policy.allow_implicit_invocation == false)
local stat = vim.uv.fs_stat(target)
save(frontmatter)
assert(vim.deep_equal(stat.mtime, vim.uv.fs_stat(target).mtime), "unchanged save rewrote YAML")

vim.fn.writefile({
  "# Keep this comment",
  "interface:",
  "  icon_small: ./assets/icon.svg # Keep this too",
  "  default_prompt: 'Use $example'",
  "policy:",
  "  allow_implicit_invocation: false",
  "dependencies:",
  "  tools:",
  "    - type: mcp",
  "      value: example",
}, target)
save({ "---", "name: renamed", "description: >-", "  Folded", "  description.", "---" })
generated = read()
assert(generated.interface.display_name == "renamed")
assert(generated.interface.short_description == "Folded description.")
assert(generated.policy.allow_implicit_invocation == true)
assert(generated.interface.icon_small == "./assets/icon.svg")
assert(generated.interface.default_prompt == "Use $example")
assert(generated.dependencies.tools[1].value == "example")
local content = table.concat(vim.fn.readfile(target), "\n")
assert(content:find("# Keep this comment", 1, true) and content:find("# Keep this too", 1, true))
save({ "---", "description: example", "disable-model-invocation: YES", "---" })
assert(read().policy.allow_implicit_invocation == false)
assert(read().interface.display_name == vim.fs.basename(directory))

local before = vim.fn.readfile(target)
for _, invalid in ipairs({
  { "---", "description: [broken", "---" },
  { "---", "description: example" },
  { "---", "description: example", "disable-model-invocation: maybe", "---" },
}) do
  local warnings = #notifications
  save(invalid)
  assert(#notifications == warnings + 1)
  assert(vim.deep_equal(before, vim.fn.readfile(target)), "invalid frontmatter changed YAML")
end
local target_buf = vim.fn.bufadd(target)
vim.fn.bufload(target_buf)
vim.bo[target_buf].modified = true
save(frontmatter)
assert(notifications[#notifications]:find("unsaved edits", 1, true))
assert(vim.deep_equal(before, vim.fn.readfile(target)))
vim.api.nvim_buf_delete(target_buf, { force = true })
vim.fn.writefile({ "interface: [broken" }, target)
save(frontmatter)
assert(vim.deep_equal({ "interface: [broken" }, vim.fn.readfile(target)))

vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(directory, "rf")
print("Skill frontmatter completion and BufWritePost sync passed")
