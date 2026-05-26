function help2comp_rec --description 'Generates fish completions by using a cli tool\'s help, recurses into sub-commands'
    argparse --move-unknown c/call-sub s/stdout -- $argv
    set -l bin $argv[1]
    set -l out_file "$bin.fish"
    set -l completions
    set -l is_sub_command false

    # 1. Extract subcommands
    echo "1. Extract subcommands"
    if string match -q "* *" $bin
        set bin (string split " " $bin)
        set is_sub_command true
    end
    set -l help_text ($bin --help | string collect)
    set -l subcommands (echo $help_text | sed -En '/(sub)?commands:/I,$p' | grep -E '^\s+[a-z0-9-]+' | awk '{print $1}' | sort -u | string match -rv "^$bin\$")

    set --append completions "# Completions for $bin"

    # 2. Determine File/Directory completion logic based on Usage/Arguments
    echo "2. Determine File/Directory completion logic based on Usage/Arguments"
    set -l usage_block (echo $help_text | grep -iE "Usage:|Arguments:" | string collect)
    set -l completion_logic ""

    if string match -qi "*DIR*" "$usage_block"; or string match -qi "*FOLDER*" "$usage_block"
        # Block files, but allow directories
        set completion_logic "complete -c $bin -f -a \"(__fish_complete_directories)\""
    else if string match -qi "*FILE*" "$usage_block"; or string match -qi "*INPUT*" "$usage_block"
        # Allow files (don't add -f)
        set completion_logic "# File completion allowed by default"
    else if set -q subcommands[1]
        # No file/dir keywords found, and subcommands exist: block both
        set completion_logic "complete -c $bin -f"
    end

    if test -n "$completion_logic"
        set --append completions "$completion_logic"
    end
    # set --append completions (help2comp --stdout "$bin" | string replace --regex "^complete -c $bin" "complete -c $bin"' -n "not __fish_seen_subcommand_from \$commands"')
    # printf '%s\n' $completions >$out_file
    # return

    # 3. Global setup
    echo "3. Global setup"
    if set -q subcommands[1]
        set --append completions "" "# Subcommands" "set -l commands $subcommands" ""

        # 4. Base Flags: Only show if NO subcommand has been typed yet
        echo "4. Base Flags: Only show if NO subcommand has been typed yet"
        set --append completions "# top-level flags"
        set --append completions (help2comp --stdout "$bin" | string replace --regex "^complete -c $bin" "complete -c $bin"' -n "not __fish_seen_subcommand_from \$commands"')

        # printf '%s\n' $completions
        # return

        # 5. Subcommand Suggestions: Also only show at the top level
        echo "5. Processing subcommands"
        set --append completions "# Subcommand completion"
        for sub in $subcommands
            echo "  - Processing $sub"
            # Get description (matches the line starting with the subcommand)
            set -l desc ($bin --help | grep -E "^\s+$sub\s+" | sed -E "s/^\s+$sub\s+//" | string collect | string escape)
            set --append completions "complete -c $bin -n \"not __fish_seen_subcommand_from \$commands\" -a \"$sub\" -d $desc"
        end

        # 6. Subcommand-specific Flags
        echo "6. Processing subcommand flags"
        set --append completions "" "" "# Completions for each subcommand" ""
        if set -q _flag_call_sub
            for sub in $subcommands
                echo "  - Processing $sub"
                # These flags ONLY show if the specific subcommand IS seen
                set --append completions (help2comp --stdout "$sub" | string replace --regex "complete -c '$bin $sub'" "complete -c $bin -f -n '__fish_seen_subcommand_from $sub'")
            end
        else
            for sub in $subcommands
                echo "  - Processing $sub"
                # These flags ONLY show if the specific subcommand IS seen
                set --append completions (help2comp --stdout "$bin $sub" | string replace --regex "complete -c '$bin $sub'" "complete -c $bin -f -n '__fish_seen_subcommand_from $sub'")
            end
        end
    else
        echo "No subcommands detected!"
        if $is_sub_command
            set --append completions (help2comp --stdout "$bin" | string replace --regex "complete -c $bin[1]" "complete -c '$bin[1]' -f -n '__fish_seen_subcommand_from $bin[2..]'")
        else
            set --append completions (help2comp --stdout "$bin")
        end
    end

    if set -q _flag_stdout
        printf '%s\n' $completions
    else
        printf '%s\n' $completions >$out_file
    end
end
