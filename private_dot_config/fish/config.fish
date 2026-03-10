#!/bin/fish
# time begin

# add extra completion paths
set -a fish_complete_path $__fish_cache_dir/completions $__fish_config_dir/completions_extra

# set variables
set -gx HAS_OCARGO 1

if set -q ___fish_cache_dir
    set -xg __fish_cache_dir "$HOME/.cache/fish"
    mkdir -p $__fish_cache_dir
end

set fresh_fish_env $__fish_cache_dir/fresh_fish_env.fish
touch $__fish_cache_dir/last_fish

set -l _last_fish (cat $__fish_cache_dir/last_fish)

# set -l session_file "/tmp/fish-session-$USER"
# if not test -e $session_file; or set -q _fresh_fish; or begin
# Run if started with _fresh_fish=1, if there is no last_fish timestamp, or if it's been one day since the last cache update
if set -q _fresh_fish; or not test -f $fresh_fish_env; or not set -q _last_fish[1]; or test (math (date +%s) - $_last_fish) -ge 86400
    set -l ppid (ps -p $fish_pid -o ppid= | string trim)
    set -l parent_comm (ps -p $ppid -o comm= | string trim)
    # echo $ppid
    # echo $parent_comm

    if string match -qi 'relay*' "$parent_comm"; or not test -f "$fresh_fish_env"
        if not string match -qi 'relay*' "$parent_comm"
            echo "Not running in a fresh shell, but Fish cache is missing."
            echo "Cache will be built, but may be dirty."
            echo "Rebuild it via fresh_fish in a new shell."
        end
        fresh_fish
    end
end

# Source fresh_fish_env cache
source $fresh_fish_env

# Source local completions cache
set -l _FISH_CACHE_COMPLETIONS_DIR $__fish_cache_dir/completions
mkdir -p $_FISH_CACHE_COMPLETIONS_DIR
for f in $_FISH_CACHE_COMPLETIONS_DIR/*.fish
    source $f
end

for f in $__fish_config_dir/completions_extra/*.fish
    source $f
end

# Set keybindings
set --global fish_key_bindings fish_vi_key_bindings

#@ functions -c fish_vi_key_bindings __original_vi_key_bindings
# functions -c fish_user_key_bindings fish_key_bindings

# function _fish_mode_prompt
#     switch $fish_bind_mode
#         case default
#             set_color --bold red
#             echo N
#         case insert
#             set_color --bold green
#             echo I
#         case replace_one
#             set_color --bold green
#             echo R
#         case replace
#             set_color --bold bryellow
#             echo R
#         case visual
#             set_color --bold brmagenta
#             echo V
#         case operator
#             set_color --bold cyan
#             echo N
#         case '*'
#             set_color --bold red
#             echo '?'
#     end
#     set_color normal
# end

# set -gx STARSHIP_LOG trace

# end
