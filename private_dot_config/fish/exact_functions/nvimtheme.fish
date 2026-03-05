function nvimtheme --wraps='nvim' --description 'alias nvimtheme="PATH=$PATH_CLEAN RECOMPILE_COLORSCHEME=true nvim"'
    PATH=$PATH_CLEAN RECOMPILE_COLORSCHEME=true $NVIM_EXECUTABLE $argv
end
