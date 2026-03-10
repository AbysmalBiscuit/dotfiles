function venv --wraps='source .venv/bin/activate.fish' --description 'alias venv=source .venv/bin/activate.fish'
    set -l venv_path (pwd)/.venv/bin/activate.fish
    if test -f $venv_path
        source $argv
        return 0
    end
    return 1
end
