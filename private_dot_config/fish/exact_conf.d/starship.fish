if type -q starship
    # set -gx __last_pwd $PWD

    function toggle_starship_config --on-variable PWD
        set -l home_pattern '^/(home|Users|mnt/c/Users)/[^/]+'
        if string match -qir "$home_pattern" "$PWD"
            if string match -qir "$home_pattern/(.config|.local|.cache|AppData|Downloads|Git)/.*\$" "$PWD"
                # Common project dirs
                set -gx STARSHIP_CONFIG ~/.config/starship.toml
                return 0
            end
            set -gx STARSHIP_CONFIG ~/.config/starship_minimal.toml
            return 0
        end
        if string match -qir '.*/Git/?.*' "$PWD"
            set -gx STARSHIP_CONFIG ~/.config/starship.toml
        else
            set -gx STARSHIP_CONFIG ~/.config/starship_minimal.toml
        end

        # switch "$PWD"
        #     case /mnt/c/Windows/*
        #         set -gx STARSHIP_CONFIG ~/.config/starship_minimal.toml
        #     case '*'
        #         # Set this back to your default config path
        #         set -gx STARSHIP_CONFIG ~/.config/starship.toml
        # end
    end
    # Run once on startup to set the initial state
    toggle_starship_config

    # function starship_transient_prompt_func
    #     starship module time
    # end

    # update vim mode
    # if test "$fish_key_bindings" = fish_vi_key_bindings; or test "$fish_key_bindings" = fish_user_key_bindings
    #     function on_fish_bind_mode --on-variable fish_bind_mode
    #         # export the vi_mode_symbol variable which Starship can use
    #         set --global --export vi_mode_symbol ""
    #
    #         # Do whatever you want here to set vi_mode_symbol...
    #         set --local color
    #         set --local char
    #         switch $fish_bind_mode
    #             case default
    #                 set color red
    #                 set symbol N
    #             case insert
    #                 set color green
    #                 set symbol I
    #             case replace replace_one
    #                 set color green
    #                 set symbol R
    #             case visual
    #                 set color brmagenta
    #                 set symbol V
    #             case '*'
    #                 set color cyan
    #                 set symbol "?"
    #         end
    #         set vi_mode_symbol (set_color --bold $color)"[$symbol]"(set_color normal)
    #         return 0
    #     end
    #     on_fish_bind_mode
    # else
    #     function on_fish_bind_mode
    #         return 1
    #     end
    # end
end
