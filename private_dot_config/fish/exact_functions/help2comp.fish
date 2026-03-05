function help2comp
    argparse --ignore-unknown s/stdout -- $argv

    set command_ $argv[1]
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

    set tmp_command (mktemp -t "help2comp.XXXXX.sh")
    echo >$tmp_command "\
#!/bin/bash
$command_ "'"$@"'

    chmod u+x $tmp_command
    # echo $tmp_command
    # ll $tmp_command
    # cat $tmp_command

    # set tmp_man "$command_.1"
    # fish_update_completions $tmp_man
    # echo $completion_file_path

    set -l python (__fish_anypython)
    or begin
        printf "%s\n" (_ "python executable not found") >&2
        return 1
    end

    if set -q _flag_stdout
        help2man "$argv[1]" | $python -B $__fish_config_dir/tools/create_manpage_completions.py --keep --stdout --stdin
    else
        help2man $tmp_command | $python -B $__fish_config_dir/tools/create_manpage_completions.py --keep --stdout --stdin >$completion_file_path
    end

    # cat $tmp_man
    # rm $tmp_command
    # rm $tmp_man
end

# function __fish_update_completions_custom --description "Update man-page based completions"
#     set -l python (__fish_anypython)
#     or begin
#         printf "%s\n" (_ "python executable not found") >&2
#         return 1
#     end
#     cat | $python -B $__fish_config_dir/tools/create_manpage_completions.py --keep --stdout --stdin
# end
