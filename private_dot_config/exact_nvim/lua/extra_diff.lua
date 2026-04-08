local M = {}

local function show_diff(mode)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local original = table.concat(lines, "\n") .. "\n"

  local tmp = vim.fn.tempname() .. ".gd"
  vim.fn.writefile(lines, tmp)

  vim.system({ "gdscript-formatter", tmp }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Formatter error: " .. (result.stderr or ""), vim.log.levels.ERROR)
        os.remove(tmp)
        return
      end

      local formatted_lines = vim.fn.readfile(tmp)
      local formatted = table.concat(formatted_lines, "\n") .. "\n"
      os.remove(tmp)

      if formatted == original then
        vim.notify("No changes — already formatted", vim.log.levels.INFO)
        return
      end

      if mode == "inline" then
        local ok, mini_diff = pcall(require, "mini.diff")
        if ok then
          mini_diff.set_ref_text(buf, formatted_lines)
          mini_diff.toggle_overlay(buf)
        else
          vim.notify("mini.diff not found", vim.log.levels.ERROR)
        end
      else
        ---@type string
        local diff = vim.text.diff(original, formatted, { result_type = "unified" })
        vim.cmd("vnew")
        local dbuf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(dbuf, 0, -1, false, vim.split(diff, "\n"))
        vim.bo[dbuf].filetype = "diff"
        vim.bo[dbuf].buftype = "nofile"
        vim.api.nvim_buf_set_name(dbuf, "gdscript-formatter diff")
        vim.bo[dbuf].modifiable = false
      end
    end)
  end)
end

function M.setup()
  vim.keymap.set("n", "<leader>qd", function()
    local ok, mini_diff = pcall(require, "mini.diff")
    if ok then
      mini_diff.set_ref_text(0, {})
    end
    vim.notify("Diff view closed", vim.log.levels.INFO)
  end, { silent = true, desc = "Close inline diff view" })

  vim.api.nvim_create_user_command("GdscriptDiff", function(opts)
    local mode = (opts.args ~= "" and opts.args) or "inline"
    show_diff(mode)
  end, {
    nargs = "?",
    desc = "Show gdscript-formatter diff (inline or summary)",
    complete = function()
      return { "inline", "diff" }
    end,
  })
end

return M
