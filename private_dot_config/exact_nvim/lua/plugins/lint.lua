-- -- Early exit if opening a manpage
-- if vim.g.is_manpage then
--   return {}
-- end

---@type LazyPluginSpec[]
return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        gdscript = { "gdradon", "gdscript_formatter", "gdlint" },
      },
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", vim.fn.expand("~/.config/markdownlint-cli2/markdownlint-cli2.yaml"), "--" },
        },
        gdlint = {
          cmd = "gdlint",
          stdin = false,
          args = {},
          env = {
            PYTHONIOENCODING = "utf-8",
            LOCALAPPDATA = vim.g.is_windows and vim.fn.getenv("LOCALAPPDATA") or "",
          },
          stream = "both",
          ignore_exitcode = true,
          condition = function(_)
            local cwd = vim.uv.cwd()
            return vim.fn.filereadable(cwd .. "/project.godot") == 1
          end,
          parser = require("lint.parser").from_pattern(
            -- Pattern: file:line: severity: message (code)
            "[^:]+:(%d+):%s+(%w+):%s+(.*)%s+%((.*)%)",
            { "lnum", "severity", "message", "code" },
            -- Map gdlint "Error" string to Neovim diagnostic levels
            {
              ["Error"] = vim.diagnostic.severity.ERROR,
              ["Warning"] = vim.diagnostic.severity.WARN,
            }
          ),
        },
        gdradon = {
          cmd = "gdradon",
          stdin = false,
          args = { "cc" },
          stream = "stdout",
          ignore_exitcode = true,
          env = {
            PYTHONIOENCODING = "utf-8",
            LOCALAPPDATA = vim.g.is_windows and vim.fn.getenv("LOCALAPPDATA") or "",
          },
          condition = function(_)
            local cwd = vim.uv.cwd()
            return vim.fn.filereadable(cwd .. "/project.godot") == 1
          end,
          parser = function(output, bufnr)
            local diagnostics = {}
            local lines = vim.split(output, "\n")
            local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

            local severity_map = {
              A = vim.diagnostic.severity.HINT,
              B = vim.diagnostic.severity.INFO,
              C = vim.diagnostic.severity.WARN,
              D = vim.diagnostic.severity.WARN,
              E = vim.diagnostic.severity.ERROR,
              F = vim.diagnostic.severity.ERROR,
            }

            local grade_desc = {
              A = "simple, easy to follow",
              B = "moderate, well-structured",
              C = "complex, consider refactoring",
              D = "too complex, hard to maintain",
              E = "very complex, should be split up",
              F = "untestable, needs rewrite",
            }

            for _, line in ipairs(lines) do
              local name, grade = line:match("[CF]%s+%d+:%d+%s+([%w_]+)%s+-%s+([A-F])%s+%(%d+%)")
              if name then
                local actual_lnum = 0
                for i, buf_line in ipairs(buf_lines) do
                  if buf_line:match("^%s*func%s+" .. name .. "%s*%(") then
                    actual_lnum = i - 1 -- 0-indexed for Neovim
                    break
                  end
                end

                table.insert(diagnostics, {
                  source = "gdradon",
                  lnum = actual_lnum,
                  col = 0,
                  severity = severity_map[grade] or vim.diagnostic.severity.HINT,
                  message = string.format("Complexity %s: %s — %s", grade, name, grade_desc[grade] or "unknown"),
                })
              end
            end
            return diagnostics
          end,
        },
        gdscript_formatter = {
          cmd = "gdscript-formatter",
          stdin = false,
          args = { "lint", "--max-line-length", "120" },
          stream = "stdout",
          ignore_exitcode = true,
          condition = function(_)
            local cwd = vim.uv.cwd()
            return vim.fn.filereadable(cwd .. "/project.godot") == 1
          end,
          parser = require("lint.parser").from_pattern(
            -- filepath:line:rule:severity: description
            "[^:]+:(%d+):([^:]+):(%w+): (.*)",
            { "lnum", "code", "severity", "message" },
            {
              ["Error"] = vim.diagnostic.severity.ERROR,
              ["Warning"] = vim.diagnostic.severity.WARN,
            },
            { source = "gdscript-formatter" }
          ),
        },
      },
    },
  },
}
