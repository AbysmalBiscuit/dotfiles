function fish_prompt --description 'Write out the prompt'
    set stat $status

    if not set -q __fish_prompt_normal
        set -g __fish_prompt_normal (set_color normal)
    end

    if not set -q __fish_color_blue
        set -g __fish_color_blue (set_color -o blue)
    end

    if not set -q __fish_prompt_green
        set -g __fish_prompt_green (set_color -o $fish_color_user)
    end

    if not set -q __fish_prompt_red
        set -g __fish_prompt_red (set_color -o red)
    end

    # Set the color for the status depending on the value
    if not set -q __fish_color_status
        set -g __fish_color_status (set_color -o red)
    end

    if test $stat -gt 0
        set __fish_color_status (set_color -o red)
        set __fish_prompt_status (printf '%s(%s)%s' "$__fish_color_status" "$stat" "$__fish_prompt_normal")
    else
        set __fish_prompt_status ""
    end

    if set -q VIRTUAL_ENV
        echo -n -s (set_color --bold 80FFBB) "(" (basename "$VIRTUAL_ENV") ")" (set_color normal) " "
    end

    switch "$USER"

        case root toor

            printf '[%s%s@%s %s%s%s]%s# ' "$__fish_prompt_red" $USER (prompt_hostname) "$__fish_color_blue" (prompt_pwd) "$__fish_prompt_normal" "$__fish_prompt_status"

        case '*'

            # printf '[%s%s@%s %s%s%s]%s(%s)%s$ ' "$__fish_prompt_green" $USER (prompt_hostname) "$__fish_color_blue" (prompt_pwd) "$__fish_prompt_normal" "$__fish_color_status" "$stat" "$__fish_prompt_normal"
            printf '[%s%s@%s %s%s%s]%s$ ' "$__fish_prompt_green" $USER (prompt_hostname) "$__fish_color_blue" (prompt_pwd) "$__fish_prompt_normal" "$__fish_prompt_status"
    end
end
