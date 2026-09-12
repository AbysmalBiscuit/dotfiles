local M = {}

function M.setup()
  local base = require("chezmoi.commands.__base")
  local execute = base.execute
  local queue = {}
  local running = false

  local function run_next()
    if running or #queue == 0 then
      return
    end
    running = true
    local opts = table.remove(queue, 1)
    local command = { "chezmoi", "apply" }
    for _, target in ipairs(opts.targets or {}) do
      table.insert(command, require("plenary.path"):new(target):expand())
    end
    vim.list_extend(command, opts.args or {})
    vim.list_extend(command, require("chezmoi").config.extra_args)
    vim.list_extend(command, { "--no-tty", "--no-pager", "--error-on-conflict" })

    local function finish(result)
      running = false
      if result.code ~= 0 then
        local message = result.code == 124 and "chezmoi apply timed out after 30 seconds"
          or "chezmoi apply failed (exit " .. result.code .. ")"
        if result.stderr and result.stderr ~= "" then
          message = message .. "\n" .. result.stderr
        end
        vim.notify(message, vim.log.levels.ERROR)
      elseif result.stderr and result.stderr ~= "" then
        vim.notify(result.stderr, vim.log.levels.WARN)
      end
      local ok, err = pcall(opts.on_exit, nil, result.code, result.signal)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
      run_next()
    end

    local ok, err = pcall(vim.system, command, { text = true, stdin = "", timeout = 30000 }, function(result)
      vim.schedule(function()
        finish(result)
      end)
    end)
    if not ok then
      finish({ code = -1, signal = 0, stderr = tostring(err) })
    end
  end

  base.execute = function(opts)
    if not opts or opts.cmd ~= "apply" or not opts.on_exit then
      return execute(opts)
    end
    table.insert(queue, vim.deepcopy(opts))
    run_next()
    return {}
  end
end

return M
