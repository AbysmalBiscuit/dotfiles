local M = { items = {}, stamp = 0, scanning = false, ttl = 30 }

local function now()
  return (vim.uv or vim.loop).hrtime() / 1e9
end

function M.fresh()
  return (now() - M.stamp) < M.ttl and #M.items > 0
end

-- async: spawns a throwaway headless nvim that runs getcompletion in ITS own
-- main thread and prints the result. Our main thread only waits on the pipe.
function M.scan(done)
  if M.scanning then
    return
  end
  M.scanning = true

  vim.system({
    vim.v.progpath,
    "--headless",
    "-u",
    "NONE",
    "+lua io.write(table.concat(vim.fn.getcompletion('', 'shellcmd'), '\\n'))",
    "+q",
  }, { text = true }, function(obj)
    if obj.code ~= 0 or not obj.stdout then
      vim.schedule(function()
        M.scanning = false
      end)
      return
    end

    local kinds = require("blink.cmp.types").CompletionItemKind
    local seen, items = {}, {}
    for name in obj.stdout:gmatch("[^\r\n]+") do
      local key = name:lower()
      if name ~= "" and not seen[key] then
        seen[key] = true
        items[#items + 1] = { label = name, kind = kinds.Text }
      end
    end

    -- callback runs off-thread; publish on the main thread
    vim.schedule(function()
      M.items = items
      M.stamp = now()
      M.scanning = false
      if done then
        done(items)
      end
    end)
  end)
end

vim.api.nvim_create_user_command("RefreshExeCache", function()
  M.stamp = 0
  M.scan()
end, {})

return M
