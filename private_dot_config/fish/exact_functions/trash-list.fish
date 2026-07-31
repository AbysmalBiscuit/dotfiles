function trash-list --wraps='trash-list' --description 'Sets TRASHDIR automatically based on current realpath'
    set -l trashdir (__get_trash_dir)
    command trash-list --trash-dir $trashdir $argv
end
