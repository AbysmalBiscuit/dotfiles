function update-nvim-plugins
    $NVIM_EXECUTABLE --headless "+Lazy! sync" '+qa!'
end
