# Defined in - @ line 1
if type -q pdu
    function du --wraps=pdu --description 'alias du=pdu'
        pdu $argv
    end
else
    echo "'pdu' is not installed on this system. Install it to replace 'du'."
    function du --wraps='du' --description 'alias du=du -h'
        du -h $argv
    end
end
