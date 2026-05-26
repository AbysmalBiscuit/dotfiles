if type -q wslinfo
    function nvim --wraps='nvim' --description 'alias nvim="PATH=$PATH_CLEAN nvim"'
        env PATH=$PATH_CLEAN $NVIM_EXECUTABLE $argv
    end
end
