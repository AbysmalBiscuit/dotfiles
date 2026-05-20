function find_float --description ''
    argparse --move-unknown 'b/bits=' p/pretty h/help -- $argv
    if set -q _flag_help
        python3 $__fish_config_dir/tools/find_float.py --help
        return
    end

    python3 $__fish_config_dir/tools/find_float.py $argv_opts $argv
end
