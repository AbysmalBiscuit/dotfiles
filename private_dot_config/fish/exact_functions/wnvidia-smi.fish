# Defined in - @ line 1
function wnvidia-smi --wraps='nvidia-smi' --description 'alias wnvidia-smi=watch -n 1 nvidia-smi'
  watch -n 1 nvidia-smi $argv;
end
