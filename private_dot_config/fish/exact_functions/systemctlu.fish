# Defined in - @ line 1
function systemctlu --wraps='systemctl' --description 'alias systemctlu=systemctl --user'
  systemctl --user $argv;
end
