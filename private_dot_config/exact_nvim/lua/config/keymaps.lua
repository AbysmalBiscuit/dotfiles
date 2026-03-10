-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local set = vim.keymap.set
local command = vim.api.nvim_create_user_command

--------------------------------------------------------------------------------
-- entering command mode
--------------------------------------------------------------------------------
-- set("n", ";", ":", { desc = "Enter command mode" })
-- set("n", ":", ";", { desc = "Go to next character" })
-- set("n", "\\", ":", { desc = "Enter command mode" })

--------------------------------------------------------------------------------
-- save file
--------------------------------------------------------------------------------
set("n", "<leader>qw", "<cmd>w<cr>", { desc = "Save file" })
set("n", "<leader>qa", "<cmd>wa<cr>", { desc = "Save all files" })
set("n", "<A-C-s>", "<cmd>wa<cr>", { desc = "Save all files" })
set("n", "<leader>qx", "<cmd>xa<cr>", { desc = "Save all files and quit" })
set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Try to quit without saving" })
set("n", "<leader>qQ", function()
  require("persistence").stop()
  local success = pcall(function()
    vim.cmd("qa")
  end)
  if not success then
    require("persistence").start()
  end
end, { desc = "Try to quit without saving session" })

--------------------------------------------------------------------------------
-- Line swaps
--------------------------------------------------------------------------------
set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

-- set("v", "<S-Down>", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
-- set("v", "<S-Up>", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

--------------------------------------------------------------------------------
-- Line split
--------------------------------------------------------------------------------
set("n", "<C-k>", "i<CR><ESC>k$", { noremap = true, silent = true, desc = "Split line before cursor" })
set(
  "n",
  "<C-j>",
  "mzJ`z<cmd>delmarks z<CR>",
  { noremap = true, silent = true, desc = "Join line below, keeping cursor position" }
)

--------------------------------------------------------------------------------
-- Swap words
--------------------------------------------------------------------------------
set("n", "<leader>msw", '"zdawel"zph', { desc = "Swap words forward" })
set("n", "<leader>msb", '"zdawbl"zph', { desc = "Swap words backward" })

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------
command("FormatAllBuffers", function()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      LazyVim.format.format({ force = false, buf = bufnr })
      -- vim.api.nvim_buf_call(bufnr, function()
      --   vim.cmd("LazyFormat")
      -- end)
    end
  end
end, { desc = "Formats all open buffers" })

set("v", "<leader>o", ":sort<cr>", { desc = "Sort selection" })

--------------------------------------------------------------------------------
--- LSP
--------------------------------------------------------------------------------
set("n", "<leader>cL", "<cmd>lsp restart<cr>", { desc = "Restart the LSP server" })

-- set("n", "K", function()
--   return vim.lsp.buf.hover({ border = "single" })
-- end, { desc = "Hover" })
-- set("n", "gK", function()
--   return vim.lsp.buf.signature_help()
-- end, { desc = "Signature Help" })
-- set("i", "<c-k>", function()
--   return vim.lsp.buf.signature_help({ border = "" })
-- end, { desc = "Signature Help" })

-- set("n", "<leader>fo", vim.lsp.buf.format, { desc = "Format current buffer using LSP" })

-- Map <leader><leader>f to format the file
-- set('n', '<leader>fo', vim.lsp.buf.format, { noremap = true, silent = true })

-- set("n", "<leader>vwm", function()
--     require("vim-with-me").StartVimWithMe()
-- end)
-- set("n", "<leader>svwm", function()
--     require("vim-with-me").StopVimWithMe()
-- end)

--------------------------------------------------------------------------------
--- Clipboard
--------------------------------------------------------------------------------
-- Greatest remap ever: Paste without overwriting register
-- set("x", "<leader>p", [["_dP]], { desc = "Paste without overwriting clipboard" })
set({ "x", "v" }, "p", "P", { silent = true, noremap = true, desc = "Paste without overwriting clipboard" })
set({ "x", "v" }, "P", "p", { silent = true, noremap = true, desc = "Paste with overwriting clipboard" })
-- set({ "x", "v" }, "<leader>p", "p", { desc = "Paste with overwriting clipboard", silent = true, noremap = true })
set({ "n" }, "Y", "y$", { silent = true, noremap = true, desc = "Yank until the end of the line" })
set({ "x", "v" }, "c", '"_c', { silent = true, noremap = true, desc = "Change without overwriting clipboard" })
set(
  { "n" },
  "C",
  '"_c$',
  { silent = true, noremap = true, desc = "Change until the end of the line, without affecting clipboard" }
)
set({ "n" }, "<leader>C", "C", { silent = true, noremap = true, desc = "Change until the end of the line" })
set(
  { "n" },
  "<leader>p",
  "v$hP",
  { silent = true, noremap = true, desc = "Paste until the end of the line without overwriting keyboard" }
)

-- paste clipboard in insert mode
set("i", "<C-p>", function()
  if not require("noice.lsp").scroll(-4) then
    -- return "<c-b>"
    return '<C-o>"+p'
  end
end, {
  expr = true,
  noremap = true,
  silent = true,
  desc = "If a floating LSP window is open, scroll up, otherwise paste clipboard in insert mode",
})

-- best remaps from reddit
--  set("n", "ycc", "yygccp", { remap = true, desc= "Yank a line, copy it and paste it after the cursor" })
set("n", "ycc", function()
  return "yy" .. vim.v.count1 .. "gcc']p"
end, { remap = true, expr = true, desc = "Yank count lines, comment them and paste them" })
set("x", "/", "<Esc>/\\%V", { noremap = true, desc = "Search within visual selection - this is magic" })

-- Next greatest remap ever: Copy to system clipboard : asbjornHaland
-- set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Copy to system clipboard" })
-- set("n", "<leader>Y", [["+Y]], { desc = "Copy entire line to system clipboard" })

-- set({ "n", "v" }, "<leader>p", [["+p]], { desc = "Paste after from system clipboard" })
-- set({ "n", "v" }, "<leader>P", [["+P]], { desc = "Paste before cursor from system clipboard" })

-- Delete without affecting clipboard
-- set({ "n", "v" }, "<leader>d", '"_d', { desc = "Delete without saving to register" })

--------------------------------------------------------------------------------
--- Snacks keymaps
--------------------------------------------------------------------------------

if not vim.g.is_manpage and _G.Snacks ~= nil then
  -- update searching settings
  -- swap grug-far and resume search keys
  set("n", "<leader>sr", function()
    Snacks.picker.resume()
  end, { desc = "Resume" })

  set({ "n", "v" }, "<leader>sR", function()
    local grug = require("grug-far")
    local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
    grug.open({
      transient = true,
      prefills = {
        filesFilter = ext and ext ~= "" and "*." .. ext or nil,
      },
    })
  end, { desc = "Search and Replace" })

  -- inspect tokens
  -- set("n", "<leader>it", "<cmd>Inspect<CR>", { desc = "Inspect the tokens under the cursor" })
  -- set("n", "<leader>ir", "<cmd>InspectTree<CR>", { desc = "Inspect the syntax tree under the cursor" })
  set("n", "<leader>uq", "<cmd>EditQuery<CR>", { desc = "Write a custom treesitter query" })

  Snacks.toggle
    .new({
      id = "hover_inspect_pos",
      name = "Inspect Pos Hover",
      get = function()
        local status, res = pcall(function()
          return #vim.api.nvim_get_autocmds({ group = "inspect_pos_hover" }) > 0
        end)
        if not status then
          return false
        end
        return res
      end,
      set = function(state)
        if state then
          vim.api.nvim_create_autocmd("CursorHold", {
            group = vim.api.nvim_create_augroup("inspect_pos_hover", { clear = false }),
            callback = function(_)
              require("hover").open({ providers = { "hover.providers.highlight" } })
            end,
            desc = "Open highlights hover on cursor hold",
          })
        else
          vim.api.nvim_clear_autocmds({ group = "inspect_pos_hover" })
        end
      end,
    })
    :map("<leader>u<C-i>")

  Snacks.toggle
    .new({
      id = "diagnostics_popup",
      name = "Diagnostics Popup",
      get = function()
        local status, res = pcall(function()
          return #vim.api.nvim_get_autocmds({ group = "DiagnosticsPopupToggle" }) > 0
        end)
        if not status then
          return false
        end
        return res
      end,
      set = function(state)
        if state then
          vim.api.nvim_create_autocmd("CursorHold", {
            group = vim.api.nvim_create_augroup("DiagnosticsPopupToggle", { clear = true }),
            callback = function()
              vim.diagnostic.open_float(nil, { focus = false })
            end,
          })
        else
          vim.api.nvim_clear_autocmds({ group = "DiagnosticsPopupToggle" })
        end
      end,
    })
    :map("<leader>uE")

  if LazyVim.has("tiny-inline-diagnostic.nvim") then
    Snacks.toggle
      .new({
        id = "virtual_text_errors",
        name = "Virtual Text Errors",
        get = function()
          return require("tiny-inline-diagnostic").enabled
        end,
        set = function(_)
          require("tiny-inline-diagnostic").toggle()
        end,
      })
      :map("<leader>ue")
  else
    Snacks.toggle
      .new({
        id = "virtual_text_errors",
        name = "Virtual Text Errors",
        get = function()
          local virtual_text = vim.diagnostic.config().virtual_text
          return virtual_text == true or type(virtual_text) == "function"
        end,
        set = function(state)
          vim.diagnostic.config({ virtual_text = state })
        end,
      })
      :map("<leader>ue")
  end

  Snacks.toggle
    .new({
      id = "virt_column",
      name = "Virt Column",
      get = function()
        return require("virt-column.config").config.enabled
      end,
      set = function(_)
        vim.cmd("VirtColumnToggle")
      end,
    })
    :map("<leader>uv")

  -- Snacks.toggle({
  --   id = "tabnine",
  --   name = "Tabnine",
  --   get = function()
  --     return vim.g.tabnine_enabled
  --   end,
  --   set = function(state)
  --     if vim.g.tabnine_enabled then
  --       vim.g.tabnine_enabled = false
  --       vim.cmd("TabnineDisable")
  --     else
  --       vim.g.tabnine_enabled = true
  --       vim.cmd("TabnineEnable")
  --     end
  --   end,
  -- }):map("<leader>uN")

  -- Snacks.toggle({
  --   id = "listchars",
  --   name = "Show list characters",
  --   get = function()
  --     return vim.opt.list
  --   end,
  --   set = function(state)
  --     vim.opt.list = not vim.opt.list
  --     -- if state then
  --     --   vim.opt.list = false
  --     -- else
  --     --   vim.opt.list = true
  --     -- end
  --     -- vim.opt.list = not vim.opt.list
  --   end,
  -- }):map("<leader>uN")

  Snacks.toggle
    .new({
      id = "blink",
      name = "Blink Completion",
      get = function()
        return vim.g.blink_cmp
      end,
      set = function(_)
        vim.g.blink_cmp = not vim.g.blink_cmp
      end,
    })
    :map("<leader>uC")

  Snacks.toggle
    .new({
      id = "persistence",
      name = "Persistence (Sessions)",
      get = function()
        return require("persistence")._active
      end,
      set = function(state)
        if state then
          require("persistence").stop()
        else
          require("persistence").start()
        end
      end,
    })
    :map("<leader>up")

  Snacks.toggle
    .new({
      id = "blink-ripgrep-manual-mode",
      name = "blink-ripgrep",
      get = function()
        return require("blink-ripgrep").config.mode == "on"
      end,
      set = function(state)
        if state then
          require("blink-ripgrep").config.mode = "on"
        else
          require("blink-ripgrep").config.mode = "off"
        end
      end,
    })
    :map("<leader>ub", { mode = { "n" } })
end

--------------------------------------------------------------------------------
--- Maps to insert text
--------------------------------------------------------------------------------

-- Automatically add semicolon or comma at the end of the line in INSERT and NORMAL modes
set("i", "<C-S-;>", "<ESC>A:")
-- set("i", "<C-:>", "<ESC>A:")
set("i", "<C-;>", "<ESC>A;")
set("i", "<C-,>", "<ESC>A,")
set("i", "<C-.>", "<ESC>A.")
set("n", "<C-S-;>", "A:<ESC>")
-- set("n", "<C-:>", "A:<ESC>")
set("n", "<C-;>", "A;<ESC>")
set("n", "<C-,>", "A,<ESC>")

-- disable certain insert mode mappings
if not LazyVim.has("tabout.nvim") then
  set("i", "<C-n>", "")
end

--------------------------------------------------------------------------------
--- Visual mode
--------------------------------------------------------------------------------

-- Block insert in line visual mode
set("x", "I", function()
  return vim.fn.mode() == "V" and "^<C-v>I" or "I"
end, { expr = true })
set("x", "A", function()
  return vim.fn.mode() == "V" and "$<C-v>A" or "A"
end, { expr = true })

set("v", "V", "gj", { noremap = true, desc = "Repeating 'V' selects more lines" })
set("v", "v", "<C-v>", { noremap = true, desc = "Double 'v' enters block visual mode" })

-- This is going to get me cancelled
-- set("i", "<C-c>", "<Esc>")

-- Cancel command
-- set("n", "Q", "<nop>", { desc = "Cancel command (disable Q)" })

-- set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

-- Quickfix navigation
-- set("n", "<C-k>", "<cmd>cnext<CR>zz", { desc = "Next quickfix item" })
-- set("n", "<C-j>", "<cmd>cprev<CR>zz", { desc = "Previous quickfix item" })

-- Location list navigation
-- set("n", "<leader>k", "<cmd>lnext<CR>zz", { desc = "Next location list item" })
-- set("n", "<leader>j", "<cmd>lprev<CR>zz", { desc = "Previous location list item" })

-- Replace word under cursor
-- set(
--   "n",
--   "<leader>s",
--   [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
--   { desc = "Replace word under cursor across file" }
-- )

-- Make file executable
-- set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make file executable" })

-- Error handling snippets (Go or similar languages)
-- set(
--   "n",
--   "<leader>ee",
--   "oif err != nil {<CR>}<Esc>Oreturn err<Esc>",
--   { desc = "Insert error-checking snippet" }
-- )
--
-- set(
--   "n",
--   "<leader>ea",
--   "oassert.NoError(err, \"\")<Esc>F\";a",
--   { desc = "Insert assertion snippet" }
-- )
--
-- set(
--   "n",
--   "<leader>el",
--   "oif err != nil {<CR>}<Esc>O.logger.Error(\"error\", \"error\", err)<Esc>F.;i",
--   { desc = "Insert logger error snippet" }
-- )

-- Edit packer configuration
-- set("n", "<leader>vpp", "<cmd>e ~/.dotfiles/nvim/.config/nvim/lua/theprimeagen/packer.lua<CR>");

-- Cellular automaton fun command
-- set(
--   "n",
--   "<leader>mr",
--   "<cmd>CellularAutomaton make_it_rain<CR>",
--   { desc = "Run CellularAutomaton 'make_it_rain'" }
-- )

-- Unmap the default <leader>f if it's already mapped
-- vim.keymap.del('n', '<leader>f')

--------------------------------------------------------------------------------
--- Change popup menu navigation in commands
--------------------------------------------------------------------------------
-- vim.api.nvim_set_keymap(
--   "c",
--   "<Down>",
--   "pumvisible() ? '<C-n>' : '<Down>'",
--   { expr = true, noremap = true, desc = "Allow using arrows to select options in popup menus" }
-- )
-- vim.api.nvim_set_keymap(
--   "c",
--   "<Up>",
--   "pumvisible() ? '<C-p>' : '<Up>'",
--   { expr = true, noremap = true, desc = "Allow using arrows to select options in popup menus" }
-- )

--------------------------------------------------------------------------------
--- Navigation/Movement `foo`
--------------------------------------------------------------------------------

-- Don't break dot repeat when tapping <left> or <right> in insert mode
set("i", "<Left>", "<c-g>U<Left>")
set("i", "<Right>", "<c-g>U<Right>")

vim.api.nvim_set_keymap(
  "i",
  "<Up>",
  "(&wrap && v:count == 0) ? '<C-o>gk' : '<Up>'",
  { expr = true, noremap = true, desc = "Move up using logical lines in insert mode when linse are wrapped" }
)

vim.api.nvim_set_keymap(
  "i",
  "<Down>",
  "(&wrap && v:count == 0) ? '<C-o>gj' : '<Down>'",
  { expr = true, noremap = true, desc = "Move down using logical lines in insert mode when lines are wrapped" }
)

-- Use home and end with g key in insert mode and when line wrapping is enabled
vim.api.nvim_set_keymap(
  "i",
  "<Home>",
  "(&wrap && v:count == 0) ? '<C-o>g<Home>' : '<Home>'",
  { expr = true, noremap = true, desc = "Move to the logical beginning of a line in insert mode" }
)

vim.api.nvim_set_keymap(
  "i",
  "<End>",
  "(&wrap && v:count == 0) ? '<C-o>g<End><Right>' : '<End>'",
  { expr = true, noremap = true, desc = "Move to the logical end of a line in insert mode" }
)

-- Smarter movement in visual mode
set(
  "x",
  "<Down>",
  "v:count == 0 && mode() ==# 'v' ? 'gj' : 'j'",
  { expr = true, noremap = true, desc = "Conditional down movement in visual modes" }
)
set(
  "x",
  "<Up>",
  "v:count == 0 && mode() ==# 'v' ? 'gk' : 'k'",
  { expr = true, noremap = true, desc = "Conditional up movement in visual modes" }
)

-- Use Tab and Shift+Tab for navigation in the popup menu
-- vim.api.nvim_set_keymap('c', '<Tab>', "pumvisible() ? '<C-n>' : '<Tab>'", { expr = true, noremap = true })
-- vim.api.nvim_set_keymap('c', '<S-Tab>', "pumvisible() ? '<C-p>' : '<S-Tab>'", { expr = true, noremap = true })

-- change tab navigation
-- set("n", "<M-S-Left>", "<cmd>tabprevious<CR>")
-- set("n", "<M-S-Right>", "<cmd>tabnext<CR>")
set({ "n", "i" }, "<M-PageUp>", "<cmd>-tabmove<CR>", { desc = "Move current tab to the left" })
set({ "n", "i" }, "<M-PageDown>", "<cmd>+tabmove<CR>", { desc = "Move current tab to the right" })

-- exit terminal mode
-- set("t", "<C-q>", [[<C-\><C-n>]], { desc = "Exit Terminal mode" })
set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Exit Terminal mode" })

-- move windows/splits
set("n", "<C-W><S-Left>", "<C-W>H", { noremap = true, silent = true, desc = "Move current window left" })
set("n", "<C-W><S-Down>", "<C-W>J", { noremap = true, silent = true, desc = "Move current window down" })
set("n", "<C-W><S-Up>", "<C-W>K", { noremap = true, silent = true, desc = "Move current window up" })
set("n", "<C-W><S-Right>", "<C-W>L", { noremap = true, silent = true, desc = "Move current window right" })

-- Page scrolling
set("n", "<C-d>", "<C-d>zz", { desc = "Page down and center the cursor", noremap = true, silent = true })
set("n", "<C-u>", "<C-u>zz", { desc = "Page up and center the cursor", noremap = true, silent = true })
set("n", "<PageDown>", "<C-d>zzzv", { desc = "Page down and center the cursor", noremap = true, silent = true })
set("n", "<PageUp>", "<C-u>zzzv", { desc = "Page up and center the cursor", noremap = true, silent = true })

-- Searching
set("n", "n", "nzzzv", { desc = "Search next occurrence, center cursor", noremap = true, silent = true })
set("n", "N", "Nzzzv", { desc = "Search previous occurrence, center cursor", noremap = true, silent = true })

-- clear search highlights
-- set("n", "<Esc>", "<cmd>nohlsearch<CR>", { noremap = true, desc = "Clear search highlights" })

-- map({ "i", "n", "s" }, "<esc>", function()
--   vim.cmd("noh")
--   LazyVim.cmp.actions.snippet_stop()
--   return "<esc>"
-- end, { expr = true, desc = "Escape and Clear hlsearch" })

-- registers
-- setup shortcuts to clear registers
--
--- Clearing registers can be done with `q + reg`
--- other comment
-- local registers = '*+"-:.%/#=_abcdefghijklmnopqrstuvwxyz0123456789'
-- for i = 1, #registers, 1 do
--   local reg = registers:sub(i, i)
--   set("n", "<leader>'d" .. reg, function()
--     vim.fn.setreg(reg, "")
--   end, { desc = "Clear register " .. reg })
-- end

-- set("n", "<leader>ch", function()
--   vim.cmd("compiler textidote")
--   vim.cmd("lmake")
-- end)

--------------------------------------------------------------------------------
--- Count words
--------------------------------------------------------------------------------
set("n", "<leader>mcl", "gvg<C-g><Esc>", { noremap = true, silent = false, desc = "Count words in the last selection" })
set("v", "<leader>mc", "g<C-g><Esc>", { noremap = true, silent = false, desc = "Count words in the current selection" })
set("n", "<leader>mc<Down>", function()
  return "mzV" .. vim.v.count1 .. "jg<C-g><ESC>`z<CMD>delmarks z<CR>"
end, { remap = true, expr = true, desc = "Get word count lines down" })
set("n", "<leader>mc<Up>", function()
  return "mzV" .. vim.v.count1 .. "kg<C-g><ESC>`z<CMD>delmarks z<CR>"
end, { remap = true, expr = true, desc = "Get word count lines up" })

-- _G.get_neigh = function(neigh_type)
--   local is_command_mode = vim.fn.mode() == "c"
--   -- Get line and add '\r' and '\n' to always return 2 characters
--   local line = is_command_mode and vim.fn.getcmdline() or vim.api.nvim_get_current_line()
--   line = "\r" .. line .. "\n"
--   -- Get start character index accounting for added '\r' at the start
--   local start = is_command_mode and vim.fn.charidx(line, vim.fn.getcmdpos()) or vim.fn.charcol(".")
--   start = start - 1
--
--   return vim.fn.strcharpart(line, start + (neigh_type == "right" and 1 or 0), neigh_type == "whole" and 2 or 1)
-- end

--------------------------------------------------------------------------------
-- Sessions
--------------------------------------------------------------------------------

vim.keymap.del("n", "<leader>qS")
vim.keymap.del("n", "<leader>qd")

--------------------------------------------------------------------------------
-- git
--------------------------------------------------------------------------------
set("n", "<leader>gq", function()
  vim.cmd('cexpr system("git diff --check --relative")')
  vim.cmd("copen")
end, { desc = "Git conflicts to quickfix" })

set(
  "n",
  "<leader>ga",
  function()
    local revision = ""
    if vim.g.diffthis_revision ~= nil and vim.g.diffthis_revision ~= "" then
      revision = " " .. vim.g.diffthis_revision
    end
    vim.cmd("Gitsigns diffthis" .. revision)

    vim.cmd([[sleep 100m]])

    -- enable soft wrap in all buffers in current window
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      vim.api.nvim_set_option_value("wrap", true, { win = win, scope = "local" })
    end
  end,
  { remap = false, expr = false, desc = "Open current file in comparison to text defined by vim.g.diffthis_revision" }
)

set("n", "<leader>gA", function()
  local completions = vim.fn.getcompletion("Gitsigns diffthis ", "cmdline")

  vim.ui.select(completions, {
    prompt = "Select diffthis_revision:",
  }, function(choice)
    if choice then
      vim.g.diffthis_revision = choice
    end
  end)
end, { desc = "Set diffthis_revision value" })

-- Define the completion function globally
_G.get_completion_leadergA = function(arg_lead, cmd_line, cursor_pos)
  local completions = vim.fn.getcompletion("Gitsigns diffthis ", "cmdline")
  return completions
end

--------------------------------------------------------------------------------
--- yank using patterns
--------------------------------------------------------------------------------
set("n", "<leader>'y", function()
  local user_input = vim.fn.input("Register, pattern, group (optional): ")
  local delimiter = user_input:sub(2, 2)
  local input = vim.fn.split(user_input, "([^" .. delimiter .. "]+)")
  local reg = input[1]
  if reg == nil then
    reg = "+"
  end
  -- Snacks.notify.info(reg)
  -- Snacks.notify.info(delimiter)
  -- Snacks.notify.info(input)
  local reg_upper = string.upper(reg)
  local pattern = input[2]

  local group_num = 1
  if input[3] ~= nil then
    group_num = input[2]
  end

  local sep = delimiter
  local separators = "!@#$%^&*;:<>,./?"
  for i = 1, #separators, 1 do
    sep = separators:sub(i, i)
    if not string.match(pattern, sep) then
      break
    end
  end
  if string.match(delimiter, ",()\\|'\"" .. reg .. reg_upper) then
    vim.notify("Failed to set a valid delimiter for command: '" .. user_input .. "'", "error")
    return
  end

  -- clear register
  vim.fn.setreg(reg, "")

  local command = "%s"
    .. sep
    .. pattern
    .. sep
    .. "\\=setreg('"
    .. reg_upper
    .. "', submatch("
    .. group_num
    .. "), 'V')"
    .. sep
    .. "gn"
  vim.notify(command, "info")
  vim.cmd(command)
end, { desc = "Prompt user for register and pattern to set a register to contain all matching instances" })

set("n", "<leader>'Y", function()
  local user_input = vim.fn.input("Register, prefixed pattern, group (optional): ")
  local delimiter = user_input:sub(2, 2)
  local input = vim.fn.split(user_input, "([^" .. delimiter .. "]+)")

  local reg = input[1]
  if reg == nil then
    reg = "+"
  end

  local reg_upper = string.upper(input[1])
  local pattern = input[2]

  -- Snacks.notify.info(delimiter)
  -- Snacks.notify.info(input)

  local group_num = 1
  if input[3] ~= nil then
    group_num = input[3]
  end

  local pattern_table = {}
  for str in string.gmatch(pattern, "([^s]+)") do
    table.insert(pattern_table, str)
  end
  local sep = pattern_table[2]:sub(1, 1)

  -- clear register
  vim.fn.setreg(reg, "")

  -- get matches
  vim.cmd(pattern .. sep .. "\\=setreg('" .. reg_upper .. "', submatch(" .. group_num .. "), 'V')" .. sep .. "gn")
end, { desc = "Prompt user for register and pattern to set a register to contain all matching instances" })
