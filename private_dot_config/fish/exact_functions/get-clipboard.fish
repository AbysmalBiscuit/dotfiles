function get-clipboard --description 'Gets the data stored in the clipboard. Equivalent to ctrl+V'
  switch (get-os)
    case "wsl"
      powershell.exe -command "Get-Clipboard" | tr -d '\r'
    case "linux"
      xclip -o -selection c
    case "darwin"
      pbpaste
  end
end