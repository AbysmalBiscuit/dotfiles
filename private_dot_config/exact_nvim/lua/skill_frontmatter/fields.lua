-- Maintain against https://code.claude.com/docs/en/skills#frontmatter-reference
-- and https://learn.chatgpt.com/docs/build-skills#optional-metadata.
---@class SkillFrontmatterField
---@field name string
---@field harnesses string[]
---@field description string
---@field values? string[]
---@field parent? string

---@type SkillFrontmatterField[]
return {
  {
    name = "name",
    harnesses = { "Claude", "Codex" },
    description = "Skill display name; falls back to the directory name. Synced to interface.display_name in agents/openai.yaml.",
  },
  {
    name = "description",
    harnesses = { "Claude", "Codex" },
    description = "Describe the task and its triggers. Codex requires this field. Also supplies the generated short description when metadata.short-description is absent.",
  },
  {
    name = "when_to_use",
    harnesses = { "Claude" },
    description = "Additional triggers appended to the skill description.",
  },
  {
    name = "argument-hint",
    harnesses = { "Claude" },
    description = "Slash-menu argument placeholder, e.g. [filename].",
  },
  {
    name = "arguments",
    harnesses = { "Claude" },
    description = "Positional $name substitutions; space-separated names or YAML list.",
  },
  {
    name = "disable-model-invocation",
    harnesses = { "Claude" },
    description = "Require manual invocation; default false. Blocks subagent preloading and scheduled invocation.\n\nThe save hook translates this into Codex's inverse policy.allow_implicit_invocation. Codex does not read this frontmatter field directly.",
    values = { "true", "false" },
  },
  {
    name = "user-invocable",
    harnesses = { "Claude" },
    description = "False hides and disables direct slash invocation; default true.",
    values = { "true", "false" },
  },
  {
    name = "allowed-tools",
    harnesses = { "Claude" },
    description = "Pre-approved tools for this turn; string or YAML list.",
  },
  {
    name = "disallowed-tools",
    harnesses = { "Claude" },
    description = "Unavailable tools for this turn; string or YAML list.",
  },
  {
    name = "model",
    harnesses = { "Claude" },
    description = "Turn or forked-subagent model; accepts /model values or inherit.",
  },
  {
    name = "effort",
    harnesses = { "Claude" },
    description = "Reasoning effort override. Supported levels depend on the model.",
    values = { "low", "medium", "high", "xhigh", "max" },
  },
  {
    name = "context",
    harnesses = { "Claude" },
    description = "Run in a separate subagent with fork.",
    values = { "fork" },
  },
  { name = "agent", harnesses = { "Claude" }, description = "Subagent type when context is fork." },
  {
    name = "background",
    harnesses = { "Claude" },
    description = "Fork asynchronously; default true. False waits for the result.",
    values = { "true", "false" },
  },
  { name = "hooks", harnesses = { "Claude" }, description = "Session hooks registered on invocation; supports once." },
  {
    name = "paths",
    harnesses = { "Claude" },
    description = "Activation file globs; comma-separated string or YAML list.",
  },
  {
    name = "shell",
    harnesses = { "Claude" },
    description = "Dynamic command shell; default bash. PowerShell must be enabled.",
    values = { "bash", "powershell" },
  },
  {
    name = "metadata",
    harnesses = { "Claude", "Codex" },
    description = "Custom YAML map. Claude stores it without interpreting it. Codex reads the nested short-description field.",
  },
  {
    name = "license",
    harnesses = { "Claude" },
    description = "Skill license. Accepted metadata; no behavioral effect.",
  },
  {
    name = "compatibility",
    harnesses = { "Claude" },
    description = "Environment prerequisites. Accepted metadata; no behavioral effect.",
  },
  {
    name = "short-description",
    parent = "metadata",
    harnesses = { "Codex" },
    description = "Concise UI summary nested under metadata. Synced to interface.short_description in agents/openai.yaml, limited to 64 characters for display.",
  },
}
