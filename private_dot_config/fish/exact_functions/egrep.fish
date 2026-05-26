# Defined in - @ line 1
function egrep --wraps='egrep' --description 'alias egrep=egrep --color=auto'
 command egrep --color=auto $argv;
end
