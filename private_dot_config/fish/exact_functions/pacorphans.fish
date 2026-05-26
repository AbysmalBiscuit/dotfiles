# Defined in - @ line 1
function pacorphans --wraps='pacman -Q' --description 'alias pacorphans=pacman -Qtdq'
  pacman -Qtdq $argv;
end
