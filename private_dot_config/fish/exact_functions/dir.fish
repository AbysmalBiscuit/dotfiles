# Defined in - @ line 1
function dir --wraps='dir' --description 'alias dir=dir --color=auto'
 command dir --color=auto $argv;
end
