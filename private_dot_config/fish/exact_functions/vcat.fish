# Defined in - @ line 1
function vcat --wraps='kitty +kitten vcat' --description 'alias vcat=kitty +kitten vcat'
  kitty +kitten vcat $argv;
end
