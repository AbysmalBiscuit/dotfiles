-- require("code_custom")

-- local is_powershell = os.getenv("PSModulePath") ~= nil
-- if is_powershell then
--   os.execute(string.format("setx YAZI_CELL_WIDTH 10", w))
--   os.execute(string.format("setx YAZI_CELL_HEIGHT 20", h))
-- end

require("mime-ext.local"):setup({
  -- Expand the existing filename database (lowercase), for example:
  with_files = {
    -- makefile = "text/makefile",
    -- ...
  },

  -- Expand the existing extension database (lowercase), for example:
  with_exts = {
    mk = "text/makefile",
    -- tex = "application/x-tex",
    sty = "text/x-tex",
    cls = "text/x-tex",
    scm = "text/plain",
    jsonl = "application/json",
    star = "text/plain",
    -- ...
  },

  -- If the mime-type is not in both filename and extension databases,
  -- then fallback to Yazi's preset `mime` plugin, which uses `file(1)`
  fallback_file1 = true,
})

require("git"):setup({
  order = 1500,
})

-- th.git = th.git or {}
-- th.git.unknown_sign = "󰞋 "
-- th.git.ignored = " "
-- th.git.untracked = "?"
-- th.git.modified_sign = "○"
-- th.git.deleted_sign = ""
-- th.git.clean_sign = "✔"

require("starship"):setup()

-- function Linemode:size_and_mtime()
--   local time = math.floor(self._file.cha.mtime or 0)
--   if time == 0 then
--     time = ""
--   elseif os.date("%Y", time) == os.date("%Y") then
--     time = os.date("%b %d %H:%M", time)
--   else
--     time = os.date("%b %d  %Y", time)
--   end
--
--   local size = self._file:size()
--   return string.format("%s %s", size and ya.readable_size(size) or "-", time)
-- end
