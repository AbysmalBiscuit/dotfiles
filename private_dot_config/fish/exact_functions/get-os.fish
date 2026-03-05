function get-os --description "Returns the OS name in lowercase characters."
  set os ""
  set desc (uname -a | string lower --)
  switch $desc
    case "*microsoft-standard-wsl*"
      set os "wsl"
    case "*linux*"
      set os "linux"
    case "*darwin*"
      set os "darwin"
    case "*"
      set os "unknown"
  end

  echo $os
end
