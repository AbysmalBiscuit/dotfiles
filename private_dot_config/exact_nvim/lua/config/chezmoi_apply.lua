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
        local message = ""
        if result.code == 124 then
          message = "chezmoi apply timed out after 30 seconds"
        else
          message = "chezmoi apply failed (exit " .. result.code .. ")"
        end

        if result.stderr and result.stderr ~= "" then
          message = message .. "\n" .. result.stderr
        end

        if string.find(result.stderr, "not in source state", 1, true) then
          local parts = vim.split(result.stderr, ":", { plain = true, trimempty = true })
          if vim.g.is_windows then
            parts[2] = parts[2] .. ":" .. parts[3]
            parts[3] = parts[4]
          end
          vim.notify(parts[1] .. ": " .. parts[3] .. parts[2], vim.log.levels.INFO)
        else
          vim.notify(message, vim.log.levels.ERROR)
        end
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
