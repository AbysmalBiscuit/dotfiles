local M = {}

function M.zoomed()
  return false
end

function M.navigate(_, direction)
  local target = ({ h = "left", j = "down", k = "up", l = "right" })[direction]
  if not target then
    return
  end
  local config = vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")
  vim.system({ "python3", config .. "/herdr/navigate.py", target, "--edge" }, { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("Herdr navigation failed: " .. result.stderr, vim.log.levels.ERROR)
      end)
    end
  end)
end

return M
