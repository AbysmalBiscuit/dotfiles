function help2comp --description 'Generates fish completions by using a cli tool\'s help'
    argparse --ignore-unknown s/stdout subcommand -- $argv
    set -l is_sub_command false
    set -l bin

    set command_ $argv[1]
    if set -q _flag_subcommand; and string match -q "* *" $command_
        set is_sub_command true
        set bin (string split " " $command_)
    end

    set completion_file_name (string replace --all ' ' '_' "$command_")".fish"

    if set -q argv[2]
        if string match --regex --quiet '.+\.fish$' "$argv[2]"
            set completion_file_path $argv[2]
        else
            set completion_file_path $argv[2]/$completion_file_name
        end
    else
        set completion_file_path $__fish_cache_dir/generated_completions/$completion_file_name
    end

    set tmp_command (mktemp -t "$command_.XXXXX.sh")
    echo >$tmp_command "\
#!/bin/bash
$command_ "'"$@"'

    chmod u+x $tmp_command

    set -l python (__fish_anypython)
    or begin
        printf "%s\n" (_ "python executable not found") >&2
        return 1
    end

    if set -q _flag_stdout
        set result (help2man "$argv[1]" | $python -B $__fish_config_dir/tools/create_manpage_completions.py --keep --stdout --stdin)

        if $is_sub_command
            printf '%s\n' $result | string replace --regex "complete -c $bin[1]" "complete -c '$bin[1]' -f -n '__fish_seen_subcommand_from $bin[2..]'"
        else
            printf '%s\n' $result
        end
    else
        help2man $tmp_command | $python -B $__fish_config_dir/tools/create_manpage_completions.py --keep --stdout --stdin >$completion_file_path
    end

    if test -f $tmp_command
        rm $tmp_command
    end
end

# function __fish_update_completions_custom --description "Update man-page based completions"
#     set -l python (__fish_anypython)
#     or begin
#         printf "%s\n" (_ "python executable not found") >&2
#         return 1
#     end
#     cat | $python -B $__fish_config_dir/tools/create_manpage_completions.py --keep --stdout --stdin
# end
