# Defined in - @ line 1
function icat --wraps='kitty +kitten icat' --description 'alias icat=kitty +kitten icat --align left'
  kitty +kitten icat --align left $argv;
end
