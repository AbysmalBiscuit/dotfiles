-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()
local gpus = wezterm.gui.enumerate_gpus()
local act = wezterm.action

config.launch_menu = {}
-- if config.launch_menu == nil then
-- end

-- determine os
local os = ""
if wezterm.target_triple == "x86_64-pc-windows-msvc" then
  os = "windows"
elseif wezterm.target_triple == "x86_64-unknown-linux-gnu" then
  os = "linux"
elseif wezterm.target_triple == "x86_64-apple-darwin" or wezterm.target_triple == "aarch64-apple-darwin" then
  os = "macos"
end

local function executable_exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local left_round = ""
local right_round = ""

-- local resize_timer = nil -- Timer to debounce the resize event

-- local function adjust_padding(window)
--   local window_dims = window:get_dimensions()
--   if not window_dims or not window_dims.pixel_height then
--     return
--   end

--   -- Grab the effective config
--   local config = window:effective_config()
--   if not config then
--     return
--   end

--   local font_size = config.font_size or 13.0
--   local line_height = config.line_height or 1.0

--   -- Approximate cell height
--   local cell_height = font_size * line_height
--   -- local cell_height = font_size * line_height * 0.95

--   if cell_height <= 0 then
--     return
--   end

--   local window_height = window_dims.pixel_height
--   local rows = math.ceil(window_height / cell_height)
--   local used_height = rows * cell_height
--   local leftover = window_height - used_height

--   local overrides = window:get_config_overrides() or {}
--   if leftover > 0 then
--     overrides.window_padding = {
--       left = 0,
--       right = 0,
--       top = leftover,
--       bottom = 0,
--     }
--   else
--     print("here")
--     return
--   end
--   print(overrides)
--   window:set_config_overrides(overrides)
-- end

-- wezterm.on('window-resized', function(window, pane)
--   adjust_padding(window)
-- end)

-- wezterm.on('window-config-reloaded', function(window)
--   adjust_padding(window)
-- end)

-- config.line_height = 1.01
config.font_size = 13.05
config.font = wezterm.font_with_fallback({
  "Sarasa Fixed K",
  "MesloLGM Nerd Font Propo",
  "Atkinson Hyperlegible Mono",
  "Noto Sans Mono CJK KR",
  "Noto Sans Mono CJK SC",
  "Noto Sans Mono CJK HK",
  "Noto Sans Mono CJK JP",
  "Noto Sans Mono CJK TC",
  "Menlo",
  "Monaco",
  "Consolas",
  "Twemoji Mozilla",
  "Apple Color Emoji",
  "Segoe UI Emoji",
  "Segoe UI Symbol",
  "Symbols Nerd Font",
  "Font Awesome 6 Pro",
})

config.color_scheme = "Catppuccin Mocha"

-- config.color_scheme = 'tokyonight'
c = {
  rosewater = "#f5e0dc",
  flamingo = "#f2cdcd",
  pink = "#f5c2e7",
  mauve = "#cba6f7",
  red = "#f38ba8",
  maroon = "#eba0ac",
  peach = "#fab387",
  yellow = "#f9e2af",
  green = "#a6e3a1",
  teal = "#94e2d5",
  sky = "#89dceb",
  sapphire = "#74c7ec",
  blue = "#89b4fa",
  lavender = "#b4befe",
  text = "#cdd6f4",
  subtext1 = "#bac2de",
  subtext0 = "#a6adc8",
  overlay2 = "#9399b2",
  overlay1 = "#7f849c",
  overlay0 = "#6c7086",
  surface2 = "#585b70",
  surface1 = "#45475a",
  surface0 = "#313244",
  base = "#1e1e2e",
  mantle = "#181825",
  crust = "#11111b",
}

-- # --> Catppuccin (Mocha)
-- set -ogq @thm_bg "#1e1e2e"
-- set -ogq @thm_fg "#cdd6f4"

-- # Colors
-- set -ogq @thm_rosewater "#f5e0dc"
-- set -ogq @thm_flamingo "#f2cdcd"
-- set -ogq @thm_rosewater "#f5e0dc"
-- set -ogq @thm_pink "#f5c2e7"
-- set -ogq @thm_mauve "#cba6f7"
-- set -ogq @thm_red "#f38ba8"
-- set -ogq @thm_maroon "#eba0ac"
-- set -ogq @thm_peach "#fab387"
-- set -ogq @thm_yellow "#f9e2af"
-- set -ogq @thm_green "#a6e3a1"
-- set -ogq @thm_teal "#94e2d5"
-- set -ogq @thm_sky "#89dceb"
-- set -ogq @thm_sapphire "#74c7ec"
-- set -ogq @thm_blue "#89b4fa"
-- set -ogq @thm_lavender "#b4befe"

-- # Surfaces and overlays
-- set -ogq @thm_subtext_1 "#a6adc8"
-- set -ogq @thm_subtext_0 "#bac2de"
-- set -ogq @thm_overlay_2 "#9399b2"
-- set -ogq @thm_overlay_1 "#7f849c"
-- set -ogq @thm_overlay_0 "#6c7086"
-- set -ogq @thm_surface_2 "#585b70"
-- set -ogq @thm_surface_1 "#45475a"
-- set -ogq @thm_surface_0 "#313244"
-- set -ogq @thm_mantle "#181825"
-- set -ogq @thm_crust "#11111b"

config.colors = {
  -- The default text color
  foreground = "#EDEDED",
  -- The default background color
  background = "#141F2E",

  -- Overrides the cell background color when the current cell is occupied by the
  -- cursor and the cursor style is set to Block
  cursor_bg = "#F0F0F0",
  -- Overrides the text color when the current cell is occupied by the cursor
  cursor_fg = "black",
  -- Specifies the border color of the cursor when the cursor style is set to Block,
  -- or the color of the vertical or horizontal bar when the cursor style is set to
  -- Bar or Underline.
  cursor_border = "#52ad70",

  -- the foreground color of selected text
  selection_fg = "white",
  -- the background color of selected text
  selection_bg = "#375780",

  -- The color of the scrollbar "thumb"; the portion that represents the current viewport
  scrollbar_thumb = c.surface2,

  ansi = {
    "#0C0C0C",
    "#CC0000",
    "#11CF45",
    "#C4A000",
    "#558EFF",
    "#75507B",
    "#06989A",
    "#D3D7CF",
  },
  brights = {
    "#555753",
    "#EF2929",
    "#2BE85F",
    "#FCE94F",
    "#91CCFF",
    "#AD7FA8",
    "#34E2E2",
    "#f0f0f0",
  },

  -- Since: 20220319-142410-0fcdea07
  -- When the IME, a dead key or a leader key are being processed and are effectively
  -- holding input pending the result of input composition, change the cursor
  -- to this color to give a visual cue about the compose state.
  compose_cursor = c.flamingo,

  -- Colors for copy_mode and quick_select
  -- available since: 20220807-113146-c2fee766
  -- In copy_mode, the color of the active text is:
  -- 1. copy_mode_active_highlight_* if additional text was selected using the mouse
  -- 2. selection_* otherwise
  copy_mode_active_highlight_bg = { Color = "#000000" },
  -- use `AnsiColor` to specify one of the ansi color palette values
  -- (index 0-15) using one of the names "Black", "Maroon", "Green",
  --  "Olive", "Navy", "Purple", "Teal", "Silver", "Grey", "Red", "Lime",
  -- "Yellow", "Blue", "Fuchsia", "Aqua" or "White".
  copy_mode_active_highlight_fg = { AnsiColor = "Black" },
  copy_mode_inactive_highlight_bg = { Color = "#52ad70" },
  copy_mode_inactive_highlight_fg = { AnsiColor = "White" },

  quick_select_label_bg = { Color = "peru" },
  quick_select_label_fg = { Color = "#ffffff" },
  quick_select_match_bg = { AnsiColor = "Navy" },
  quick_select_match_fg = { Color = "#ffffff" },

  indexed = { [16] = c.peach, [17] = c.rosewater },

  visual_bell = c.surface0,

  -- The color of the split lines between panes
  split = c.overlay0,

  tab_bar = {
    background = c.crust,
    active_tab = {
      bg_color = c.mauve,
      fg_color = c.crust,
    },
    inactive_tab = {
      bg_color = c.mantle,
      fg_color = c.text,
    },
    inactive_tab_hover = {
      bg_color = c.base,
      fg_color = c.text,
    },
    new_tab = {
      bg_color = c.surface0,
      fg_color = c.text,
    },
    new_tab_hover = {
      bg_color = c.surface1,
      fg_color = c.text,
    },
    -- fancy tab bar
    -- inactive_tab_edge = c.surface0,
  },
}

config.command_palette_fg_color = c.text
config.command_palette_bg_color = c.crust

config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}
config.allow_square_glyphs_to_overflow_width = "WhenFollowedBySpace"

config.underline_thickness = "2pt"
config.underline_position = "-20px"

-- window header configuration
config.window_decorations = "TITLE|INTEGRATED_BUTTONS|RESIZE"

config.window_frame = {
  font = require("wezterm").font("Roboto"),
  font_size = 13,
  active_titlebar_bg = c.crust,
  active_titlebar_fg = c.text,
  inactive_titlebar_bg = c.crust,
  inactive_titlebar_fg = c.text,
  button_fg = c.text,
  button_bg = c.base,
}

config.hide_tab_bar_if_only_one_tab = false
config.tab_and_split_indices_are_zero_based = false

-- This function returns the suggested title for a tab.
-- It prefers the title that was set via `tab:set_title()`
-- or `wezterm cli set-tab-title`, but falls back to the
-- title of the active pane in that tab.
function tab_title(tab_info)
  local title = tab_info.tab_title
  -- if the tab title is explicitly set, take that
  if title and #title > 0 then
    return title
  end
  -- Otherwise, use the title from the active pane
  -- in that tab
  return tab_info.active_pane.title
end

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local background = c.crust
  local left_bg = c.mantle
  local left_fg = c.overlay2
  local left_num_bg = c.overlay2
  local left_num_fg = c.mantle
  local text_bg = c.surface0
  local text_fg = c.text

  if tab.is_active then
    left_bg = background
    left_fg = c.mauve
    text_bg = c.surface1
    left_num_bg = c.mauve
  elseif hover then
    background = c.base
  end

  local title = tab_title(tab)

  -- ensure that the titles fit in the available space,
  -- and that we have room for the edges.
  title = wezterm.truncate_right(title, max_width - 2)

  return {
    { Background = { Color = left_bg } },
    { Foreground = { Color = left_fg } },
    { Text = left_round },
    { Background = { Color = left_num_bg } },
    { Foreground = { Color = left_num_fg } },
    { Text = "" .. tab.tab_index + 1 .. " " },
    { Background = { Color = text_bg } },
    { Foreground = { Color = text_fg } },
    { Text = " " .. title },
    { Background = { Color = background } },
    { Foreground = { Color = text_bg } },
    { Text = right_round },
  }
end)

-- local format_status = function(icon, icon_opts, text, text_opts)
-- local icon = icon or ""
-- local icon_opts = icon_opts or { bg = c.sapphire, fg = c.crust }
-- local text = text or ""
-- local text_opts = text_opts or { bg = c.surface0, fg = c.crust }

-- return wezterm.format({
-- { Foreground = { Color = icon_opts.bg } },
-- { Background = { Color = icon_opts.fg } },
-- { Text = left_round },
-- }) .. wezterm.format({
-- { Foreground = { Color = icon_opts.fg } },
-- { Background = { Color = icon_opts.bg } },
-- { Text = icon .. " " },
-- }) .. wezterm.format({
-- { Foreground = { Color = text_opts.fg } },
-- { Background = { Color = text_opts.bg } },
-- { Text = " " .. text .. " " },
-- })
-- end

wezterm.on("update-right-status", function(window, pane)
  if not pane or not pane:get_current_working_dir() then
    return
  end
  local name = window:active_key_table()
  if name then
    name = "TABLE: " .. name
  end

  window:set_right_status(
    -- wezterm.format({
    --   { Foreground = { Color = c.sapphire } },
    --   { Background = { Color = c.mantle } },
    --   { Text = left_round },
    -- }) ..
    -- wezterm.format({
    --   { Foreground = { Color = c.crust } },
    --   { Background = { Color = c.sapphire } },
    --   { Text = " " },
    -- }) ..
    -- wezterm.format({
    --   { Foreground = { Color = c.text } },
    --   { Background = { Color = c.surface0 } },
    --   { Text = date },
    -- })

    -- working date status
    -- format_status(
    --   " ",
    --   { bg = c.sapphire, fg = c.crust },
    --   wezterm.strftime(" %Y-%m-%d %H:%M "),
    --   { bg = c.surface0, fg = c.text }
    -- ) ..
    name or ""
  )
end)

-- keybinding definitions
local function isViProcess(pane)
  -- get_foreground_process_name On Linux, macOS and Windows,
  -- the process can be queried to determine this path. Other operating systems
  -- (notably, FreeBSD and other unix systems) are not currently supported
  return pane:get_foreground_process_name():find("n?vim") ~= nil
    or pane:get_title():find("^n?vim") ~= nil
    or (pane:get_title():find("n?vim") ~= nil and not pane:get_current_working_dir())
end

local function conditionalActivatePane(window, pane, pane_direction, vim_direction)
  if isViProcess(pane) then
    -- print("in vim sending", pane_direction)
    window:perform_action(
      -- This should match the keybinds you set in Neovim.
      act.SendKey({ key = vim_direction, mods = "CTRL" }),
      pane
    )
  else
    -- print("not in vim sending", pane_direction)
    window:perform_action(act.ActivatePaneDirection(pane_direction), pane)
  end
end

wezterm.on("ActivatePaneDirection-right", function(window, pane)
  conditionalActivatePane(window, pane, "Right", "RightArrow")
end)
wezterm.on("ActivatePaneDirection-left", function(window, pane)
  conditionalActivatePane(window, pane, "Left", "LeftArrow")
end)
wezterm.on("ActivatePaneDirection-up", function(window, pane)
  conditionalActivatePane(window, pane, "Up", "UpArrow")
end)
wezterm.on("ActivatePaneDirection-down", function(window, pane)
  conditionalActivatePane(window, pane, "Down", "DownArrow")
end)

config.leader = { key = "\\", mods = "CTRL|SHIFT" }
config.keys = {
  -- CTRL+SHIFT+Space, followed by 'r' will put us in resize-pane
  -- mode until we cancel that mode.
  {
    key = "r",
    mods = "LEADER",
    action = act.ActivateKeyTable({
      name = "resize_pane",
      one_shot = false,
    }),
  },
  -- CTRL+SHIFT+Space, followed by 'a' will put us in activate-pane
  -- mode until we press some other key or until 1 second (1000ms)
  -- of time elapses
  {
    key = "a",
    mods = "LEADER",
    action = act.ActivateKeyTable({
      name = "activate_pane",
      timeout_milliseconds = 1000,
    }),
  },

  -- CTRL-SHIFT-l activates the debug overlay
  { key = "L", mods = "CTRL", action = wezterm.action.ShowDebugOverlay },

  -- open new tab with profile 2
  {
    key = "2",
    mods = "CTRL|SHIFT",
    action = wezterm.action.SpawnTab({
      DomainName = "WSL:kali-linux",
    }),
  },

  -- for nvim navigation
  { key = "LeftArrow", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-left") },
  { key = "DownArrow", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-down") },
  { key = "UpArrow", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-up") },
  { key = "RightArrow", mods = "CTRL", action = act.EmitEvent("ActivatePaneDirection-right") },
  { key = "PageUp", mods = "ALT", action = act.ScrollByPage(1) },
  { key = "PageDown", mods = "ALT", action = act.ScrollByPage(-1) },
  { key = "PageUp", mods = "SHIFT", action = wezterm.action.DisableDefaultAssignment },
  { key = "PageDown", mods = "SHIFT", action = wezterm.action.DisableDefaultAssignment },
  { key = "PageUp", mods = "CTRL", action = wezterm.action.DisableDefaultAssignment },
  { key = "PageDown", mods = "CTRL", action = wezterm.action.DisableDefaultAssignment },
  { key = "PageUp", mods = "CTRL|SHIFT", action = wezterm.action.ActivateTabRelative(-1) },
  { key = "PageDown", mods = "CTRL|SHIFT", action = wezterm.action.ActivateTabRelative(1) },
  { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },

  -- escape sequences
  { key = ";", mods = "CTRL", action = act.SendKey({ key = ";", mods = "CTRL" }) },
  { key = ",", mods = "CTRL", action = act.SendKey({ key = ",", mods = "CTRL" }) },
  { key = ";", mods = "CTRL|SHIFT", action = act.SendKey({ key = ":", mods = "CTRL" }) },
}

config.key_tables = {
  -- Defines the keys that are active in our resize-pane mode.
  -- Since we're likely to want to make multiple adjustments,
  -- we made the activation one_shot=false. We therefore need
  -- to define a key assignment for getting out of this mode.
  -- 'resize_pane' here corresponds to the name="resize_pane" in
  -- the key assignments above.
  resize_pane = {
    { key = "LeftArrow", action = act.AdjustPaneSize({ "Left", 1 }) },
    { key = "h", action = act.AdjustPaneSize({ "Left", 1 }) },

    { key = "RightArrow", action = act.AdjustPaneSize({ "Right", 1 }) },
    { key = "l", action = act.AdjustPaneSize({ "Right", 1 }) },

    { key = "UpArrow", action = act.AdjustPaneSize({ "Up", 1 }) },
    { key = "k", action = act.AdjustPaneSize({ "Up", 1 }) },

    { key = "DownArrow", action = act.AdjustPaneSize({ "Down", 1 }) },
    { key = "j", action = act.AdjustPaneSize({ "Down", 1 }) },

    -- Cancel the mode by pressing escape
    { key = "Escape", action = "PopKeyTable" },
  },

  -- Defines the keys that are active in our activate-pane mode.
  -- 'activate_pane' here corresponds to the name="activate_pane" in
  -- the key assignments above.
  activate_pane = {
    { key = "LeftArrow", action = act.ActivatePaneDirection("Left") },
    { key = "h", action = act.ActivatePaneDirection("Left") },

    { key = "RightArrow", action = act.ActivatePaneDirection("Right") },
    { key = "l", action = act.ActivatePaneDirection("Right") },

    { key = "UpArrow", action = act.ActivatePaneDirection("Up") },
    { key = "k", action = act.ActivatePaneDirection("Up") },

    { key = "DownArrow", action = act.ActivatePaneDirection("Down") },
    { key = "j", action = act.ActivatePaneDirection("Down") },
  },
}

config.mouse_bindings = {
  {
    event = { Drag = { streak = 1, button = "Left" } },
    mods = "SUPER",
    action = wezterm.action.StartWindowDrag,
  },
  {
    event = { Drag = { streak = 1, button = "Left" } },
    mods = "CTRL|SHIFT",
    action = wezterm.action.StartWindowDrag,
  },
  -- Disable the default click behavior
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = wezterm.action.DisableDefaultAssignment,
  },
  -- Ctrl-click will open the link under the mouse cursor
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "CTRL",
    action = wezterm.action.OpenLinkAtMouseCursor,
  },
  -- Disable the Ctrl-click down event to stop programs from seeing it when a URL is clicked
  {
    event = { Down = { streak = 1, button = "Left" } },
    mods = "CTRL",
    action = wezterm.action.Nop,
  },
}

-- gpu configuration
if os == "windows" then
  config.webgpu_preferred_adapter = gpus[1]
  config.front_end = "WebGpu"
  config.max_fps = 117
  config.animation_fps = 10
end

if os == "macos" then
  config.webgpu_preferred_adapter = gpus[1]
  config.front_end = "WebGpu"
  config.max_fps = 60
  config.animation_fps = 10
  config.font_size = 14
  -- config.freetype_load_target = "HorizontalLcd"
  -- config.freetype_load_flags = 'NO_HINTING';
  config.freetype_load_target = "Mono"
  config.freetype_render_target = "Light"
end

config.exec_domains = {}

-- shell settings
if os == "windows" then
  local cmd_args
  if executable_exists("c:/clink/clink_x64.exe") then
    -- And inject clink into the command prompt
    cmd_args = { "cmd.exe", "/s", "/k", "C:/clink/clink_x64.exe", "inject", "-q" }
  else
    cmd_args = { "cmd.exe" }
  end
  config.default_prog = cmd_args

  local changed_default_prog = false
  if executable_exists("C:\\Program Files\\PowerShell\\7\\pwsh.exe") then
    table.insert(config.launch_menu, {
      label = "PowerShell7",
      args = { "C:\\Program Files\\PowerShell\\7\\pwsh.exe" },
    })
    config.default_domain = "local"
    config.default_prog = { "C:\\Program Files\\PowerShell\\7\\pwsh.exe" }
    changed_default_prog = true
  end

  if executable_exists("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe") then
    table.insert(config.launch_menu, {
      label = "PowerShell",
      args = { "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" },
    })
    if not changed_default_prog then
      config.default_domain = "local"
      config.default_prog = { "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" }
    end
  end

  config.set_environment_variables = {}
  -- Use OSC 7 as per the above example
  config.set_environment_variables["prompt"] = "$E]7;file://localhost/$P$E\\$E[32m$T$E[0m $E[35m$P$E[36m$_$G$E[0m "

  -- use a more ls-like output format for dir
  -- config.set_environment_variables["DIRCMD"] = "/d"

  table.insert(config.launch_menu, {
    label = "CMD",
    args = cmd_args,
  })

  local wsl_domains = wezterm.default_wsl_domains()
  if #wsl_domains > 0 then
    config.wsl_domains = wsl_domains

    for _, dom in ipairs(wsl_domains) do
      if dom.distribution == "kali-linux" then
        table.insert(config.launch_menu, 2, {
          label = dom.name,
          args = { "wsl.exe", "--distribution", dom.distribution },
        })
      else
        table.insert(config.launch_menu, {
          label = dom.name,
          args = { "wsl.exe", "--distribution", dom.distribution },
        })
      end
    end

    -- if not changed_default_prog then
    --   -- setting domain to WSL:... will start wsl when opening wezterm
    --   -- setting domain to local will start one of the Windows shells
    --   -- config.default_domain = "WSL:kali-linux"
    -- end
    -- config.default_domain = "WSL:kali-linux"
    config.default_prog = { "wsl.exe" }
    -- config.default_prog =
  end

  table.insert(
    config.exec_domains,
    wezterm.exec_domain("spotify", function(cmd)
      -- wezterm.log_info(cmd)

      return cmd
    end)
  )
end

config.window_close_confirmation = "NeverPrompt"
-- config.clean_exit_codes = { 0 }
-- config.exit_behavior = "Close"

config.automatically_reload_config = true

-- and finally, return the configuration to wezterm
return config
