@echo off
if defined NVIM (
    nvim --server %NVIM% --remote-send "<C-\><C-n>:close<CR>"
    nvim --server %NVIM% --remote-tab %1
) else (
    nvim -- %1
)
