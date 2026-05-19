local cmd
if vim.g.is_windows then
  local python_exe
  if vim.fn.executable("python3") then
    python_exe = "python3"
  elseif vim.fn.executable("python") then
    python_exe = "python"
  end

  if python_exe ~= "" then
    cmd = { python_exe, vim.fn.stdpath("config") .. "/after/lsp/pyrefly_lsp_wrapper.py" }
  elseif vim.fn.executable("uv") then
    cmd = { "uv", "run", vim.fn.stdpath("config") .. "/after/lsp/pyrefly_lsp_wrapper.py" }
  else
    cmd = { "pyrefly", "lsp" }
  end
else
  cmd = {
    "bash",
    "-c",
    "pyrefly lsp 2> >(grep -v '^\\s*INFO' >&2)",
  }
  cmd = { "bash", "-c", "pyrefly lsp 2> >(grep --line-buffered -v '^ INFO' >&2)" }
end

---@type vim.lsp.Config
return {
  -- cmd = { "pyrefly", "lsp" },
  cmd = cmd,
  filetypes = { "python", "pyrex", "cython" },
  root_markers = {
    "pyrefly.toml",
    "pyproject.toml",
    "setup.py",
    "setup.cfg",
    "requirements.txt",
    "Pipfile",
    ".git",
  },
  settings = {
    python = {
      pyrefly = {
        displayTypeError = "force-on",
        disableLanguageServices = false,
      },
    },
  },
  handlers = {
    -- Intercept window/logMessage to filter by severity
    ["window/logMessage"] = function(_, result, ctx)
      -- Severity levels: 1:Error, 2:Warning, 3:Info, 4:Log
      vim.notify(vim.inspect(result))
      vim.notify(vim.inspect(ctx))
      if result.type <= 2 then
        vim.lsp.handlers["window/logMessage"](_, result, ctx)
      end
      -- Everything else is ignored and won't hit the log
    end,
  },
  on_exit = function(code, _, _)
    vim.notify("Closing Pyrefly LSP exited with code: " .. code, vim.log.levels.INFO)
  end,
}
