#Requires -Version 7
# Stop all psmux processes and install the freshly built binaries from the
# psmux repo into ~/.cargo/bin. Save sessions first (prefix+Ctrl-s) if needed.
$src = "$HOME\Git\github\psmux\target\release"
$dst = "$HOME\.cargo\bin"

psmux kill-server 2>$null
Get-Process tmux, psmux, pmux -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Copy-Item "$src\psmux.exe", "$src\pmux.exe", "$src\tmux.exe" $dst -Force

Get-Item "$dst\psmux.exe", "$dst\pmux.exe", "$dst\tmux.exe" |
    Select-Object Name, Length, LastWriteTime
