function superpowers-flow --description 'alias superpowers-flow="python3 ~/.claude/superpowers-flow.py"'
    if type -q claude
        $PYTHON3_HOST_PROG ~/.claude/superpowers-flow.py
    end
end
