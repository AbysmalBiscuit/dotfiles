function set-clipboard --description 'Stores the received data to the clipboard. Equivalent to ctrl+C'
  if test -n "$argv"
    set data "$argv"
  else if ! isatty stdin
    read -z data
  else
    echo "No data received to store in clipboard" 1>&2
    return 1
  end

  switch (get-os)
    case "wsl"
      echo -n "$data" | unix2dos | clip.exe
    case "linux"
      echo -n "$data" | xclip -selection c
    case "darwin"
      echo -n "$data" | pbcopy
  end
end
