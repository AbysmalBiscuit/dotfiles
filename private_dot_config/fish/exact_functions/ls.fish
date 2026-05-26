if type -q eza
    function ls --wraps='eza --color=auto --icons=auto --classify=auto' --description 'alias ll="eza --color=auto --icons=auto --classify=auto"'
        eza --color=auto --icons=auto --classify=auto $argv
    end
else
    function ls --wraps='ls --color=auto' --description 'alias ll="ls --color=auto"'
        ls -ahl --color=auto $argv
    end
end
