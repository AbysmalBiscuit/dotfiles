if string.match(get_application_name(), "Zotero") then
  --app_* are the nautilus window dimensions
  --pos_* are the final nautilus window position coordinates
  --screen_* are the screen dimensions
  local app_x, app_y, pos_x, pos_y, screen_x, screen_y
  screen_x, screen_y = table.unpack({get_screen_geometry()})
  temp1, temp2, app_x, app_y = table.unpack({get_window_geometry()})
  temp1, temp2 = nil, nil
  pos_x = screen_x - app_x
  pos_y = 0
  set_window_position2(pos_x, pos_y)
end
