function fresh_fish --description "Generate completions and other useful items on demand"
    echo "Fishing..."
    set -l _FISH_CACHE_COMPLETIONS_DIR $__fish_cache_dir/completions
    set fish_user_paths
    set fresh_fish_env $__fish_cache_dir/fresh_fish_env.fish
    for file in $__fish_cache_dir/last_fish $fresh_fish_env
        if test -f $file
            chmod 600 $file
        end
    end
    for comp_dir in $__fish_cache_dir/completions $__fish_cache_dir/generated_completions
        if test -d $comp_dir
            chmod 700 $comp_dir
            set -l targets $comp_dir/* $comp_dir/.*
            if count $targets >/dev/null
                chmod 600 $targets
            end
        end
    end

    # Update completions from manpages in the background
    # set -x fish_update_completions_detach true
    # fish_update_completions
    # set -u fish_update_completions_detach

    function _append_to_fresh_fish_env --description 'Appends variable declarations to the cached environment variable file.'
        echo "$argv[1] $argv[2..-1]" >>$fresh_fish_env
    end

    if test -f $fresh_fish_env
        echo "" >$fresh_fish_env
    end

    # Start setting up completions
    set all_completions
    for dir_ in $fish_complete_path
        if not test -d $dir_
            continue
        end
        set --append all_completions (fd --print0 --type file '\.fish$' $dir_ --exec basename --suffix=".fish" '{}' | string split0)
    end
    set all_completions (printf "%s\n" $all_completions | sort -u)
    echo "Caught all_completions"

    # Set rust related variables
    if test -d $HOME/.cargo; and command -q rustup
        if test -d $HOME/.cargo/registry/src
            set cargo_src_completions (fd --print0 --type f -E '*zellij*' --full-path '.*completions?/.*\.fish$' "$HOME/.cargo/registry/src" | string split0)

            set final_cargo_completions
            for comp in $cargo_src_completions
                if not contains (path basename --no-extension $comp) $all_completions
                    set --append final_cargo_completions $comp
                end
            end

            if test (count $final_cargo_completions) -ge 1
                _append_to_fresh_fish_env "set -gx _CARGO_COMPLETION_PATHS" $final_cargo_completions
            end
        end
        echo "Caught all the rust environment"
    end

    echo "Caught all the environment variables"

    # Source argc if available and last, to make sure that commands that can generate their own completions will do so
    if test -d $HOME/Git/github/argc-completions
        if not type -q argc; or not type -q yq; or not type -q gawk
            # which argc
            # which yq
            # which gawk
            # cd $HOME/Git/github/argc-completions
            # bash ./scripts/download-tools.sh
            # set --append fish_user_paths $HOME/Git/github/argc-completions/bin
        end
        set -gx ARGC_COMPLETIONS_ROOT "$HOME/Git/github/argc-completions"
        set -gx ARGC_COMPLETIONS_PATH "$ARGC_COMPLETIONS_ROOT/completions/macos:$ARGC_COMPLETIONS_ROOT/completions"

        # Find all executables
        set all_executables
        for dir_ in $PATH
            if string match --regex --all --quiet '^/mnt/.*' $dir_
                continue
            end
            if not test -d $dir_
                continue
            end
            set --append all_executables (fd --print0 --type executable -E '*.so' -E '*.so.*' -E '*.dll' -E '*.dylib' . $dir_ --exec basename '{}' | string split0)
        end
        set all_executables (printf "%s\n" $all_executables | sort -u)

        # To add completions for only the specified command, modify next line e.g. set argc_scripts cargo git
        # set argc_scripts (ls -p -1 "$ARGC_COMPLETIONS_ROOT/completions/macos" "$ARGC_COMPLETIONS_ROOT/completions" | sed -n 's/\.sh$//p')
        set all_completions
        for dir_ in $fish_complete_path
            if not test -d $dir_
                continue
            end
            set --append all_completions (fd --print0 --type file '\.fish$' $dir_ --exec basename --suffix=".fish" '{}' | string split0)
        end
        set all_completions (printf "%s\n" $all_completions | sort -u)

        set argc_completions (fd --type file '\.sh$' $ARGC_COMPLETIONS_ROOT --exec basename --suffix=".sh" '{}')
        set argc_completions (printf "%s\n" $argc_completions | sort -u)

        set argc_scripts
        for comp in $argc_completions
            if contains $comp $all_executables; and contains $all_completions
                set --append argc_scripts $comp
            end
        end

        # To rebuild the list of extra available commands run:
        # set general_argc_scripts (ls -p -1 "$ARGC_COMPLETIONS_ROOT/completions" | sed -n 's/\.sh$//p')
        # set extra_argc_scripts
        # for script in $general_argc_scripts
        #     if type -q $script
        #         set extra_argc_scripts $extra_argc_scripts $script
        #     end
        # end

        argc --argc-completions fish $argc_scripts >$_FISH_CACHE_COMPLETIONS_DIR/from_argc.fish

        echo "Caught all the argc completions"
    end

    _append_to_fresh_fish_env "set -gx fish_user_paths" $fish_user_paths

    date +%s >$__fish_cache_dir/last_fish
end

if [ "$argv[1]" = runme ]
    fresh_fish
end
