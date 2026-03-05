# Defined in - @ line 1
function wsensors --wraps='sensors' --description 'alias wsensors=watch -n 1 sensors'
  watch -n 1 sensors $argv;
end
