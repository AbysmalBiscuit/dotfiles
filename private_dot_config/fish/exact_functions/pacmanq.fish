# Defined in - @ line 1
function pacmanq --wraps='grep' --description 'alias pacmanq=pacman -Q | grep'
  pacman -Q | grep $argv;
end
