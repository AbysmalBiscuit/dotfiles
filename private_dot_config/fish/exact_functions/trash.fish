function trash --wraps='trash' --description 'Sets TRASHDIR automatically based on current realpath'
    set -l trashdir (__get_trash_dir)
    command trash --trash-dir $trashdir $argv
end
