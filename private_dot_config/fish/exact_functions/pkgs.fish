set -l langs bun go rust
set -l install_commands "bun install -g PACKAGE" "go install PACKAGE" "cargo install PACKAGE"
set -l commands 'check|full' list missing
set -l pkg_info_file "$HOME/.config/fish/pkgs.csv"
set -g use_emoji false
set -g pkgs

function pkgs -V langs -V install_commands -V commands -V pkg_info_file --description 'Convenience function to call any package listing fuction'
    argparse --name="pkgs" --move-unknown h/help e/emoji -- $argv
    or return

    if set -q _flag_emoji
        set -g use_emoji true
    end

    set -l num_args (count $argv)

    if set -q _flag_help; or test $num_args -ne 2
        set -l help_exit_status 0
        if not set -q _flag_help; and test $num_args -eq 0
            echo "Error: No subcommands specified"
            echo "Need to specify a subcommand: $commands"
            echo
            set help_exit_status 1
        else if test $num_args -ge 3
            echo "Error: Too many subcommands: $argv"
            echo "Only one subcommand allowed."
            echo
            set help_exit_status 1
        end
        __pkgs_help --name="$lang" --install-command="$install_command"
        return $help_exit_status
    end

    set -l lang_patterns (__make_subword_patterns $langs)

    set -l input_lang $argv[1]
    set -e argv[1]
    set -l found_index 0
    for i in (seq (count $lang_patterns))
        if string match --quiet --regex --entire $lang_patterns[$i] $input_lang
            set found_index $i
            break
        end
    end

    if not test $found_index -gt 0
        echo "Error: '$input_lang' does not match any known language."
        echo "Available: $langs"
        echo
        __pkgs_help_lang
        return 1
    end

    if test $found_index -eq 0
        echo "Need to specify language: $langs"
        echo
        __pkgs_help_lang
        return 1
    end

    set -l lang $langs[$found_index]
    # echo "$lang install command: $install_commands[$found_index]"

    set -l install_command $install_commands[$found_index]

    # Process the rest of the command

    set -l command_patterns (__make_subword_patterns $commands)

    set -l com $argv[1]
    set -l found_index 0
    for i in (seq (count $command_patterns))
        if string match --quiet --regex --entire $command_patterns[$i] $com
            set found_index $i
            break
        end
    end

    if test $found_index -eq 0
        echo "Error: Need to specify language: $langs"
        echo
        __pkgs_help_lang --lang=$lang --install-command=$install_command
        return 1
    end
    set -l command $commands[$found_index]

    # echo "To install a package: $install_command"
    # echo

    # Load pkg info
    # if string match --quiet --regex '.*\n.*' $_flag_packages
    #     set pkgs (string trim -- $_flag_packages | string split \n)
    # else
    #     set pkgs (string trim -- $_flag_packages | string split ' ')
    # end
    set -g pkgs (cat $pkg_info_file | string split \n | string match --all --regex '^'"$lang,.+")
    # set pkgs $pkgs[2..-1]

    switch $command
        case "check|full"
            __loop_pkgs __pkgs_installed
            # for pkg in $pkgs
            #     __pkgs_installed $pkg
            # end
        case list
            for pkg in $pkgs
                set pkg (echo -n $pkg | string split ,)
                set lang $pkg[1]
                set name $pkg[2]
                set desc $pkg[3]
                set url $pkg[4]
                set git $pkg[5]

                echo $name
            end
        case missing
            set -l any_missing 0
            for pkg in $pkgs
                if not type -q $pkg
                    set any_missing 1

                    set pkg (echo -n $pkg | string split ,)
                    set lang $pkg[1]
                    set name $pkg[2]
                    set desc $pkg[3]
                    set url $pkg[4]
                    set git $pkg[5]

                    echo $name is not installed
                end
            end
            if test $any_missing -eq 0
                echo "No missing packages from: $_flag_name"
            end
    end
end

function __loop_pkgs
    for pkg in $pkgs
        $argv (__split_pkg $pkg)
    end
end

function __pkgs_installed
    # argparse e/emoji -- $argv
    # or return

    # set pkg (echo $argv[1] | string split ,)
    # set pkg (__split_pkg $argv[1])
    # set lang $pkg[1]
    # set name $pkg[2]
    # set desc $pkg[3]
    # set url $pkg[4]
    # set git $pkg[5]
    # set install_command $pkg[6]
    # set completions_command $pkg[7]
    set lang $argv[1]
    set name $argv[2]
    set desc $argv[3]
    set url $argv[4]
    set git $argv[5]
    set install_command $argv[6]
    set completions_command $argv[7]
    # printf '%s\n' $lang $name $description $website $git $install_command $completions_command 1>&2

    if $use_emoji
        if type -q $name
            echo "✅ $name"
        else
            echo "❌$name"
        end
    else
        if type -q $pkg
            echo "$name is installed"
        else
            echo "$name is not installed"
        end
    end
end

function __pkgs_help --inherit-variable langs
    set langs_list (printf '  %s\n' $langs)

    echo "\
$_flag_lang install command: $_flag_install_command

Usage: pkgs [OPTIONS] LANG COMMAND

Languages:
$langs_list

Commands:
  list          List all packages
  check|full    List packages and check which ones are installed
  missing       List only missing packages

Options:
  -h, --help    Print this help message and exit
  -e, --emoji   Use emoji in output"
end

function __pkgs_help_lang
    argparse --strict-longopts 'lang=' 'install-command=' -- $argv
    or return

    echo "\
$_flag_lang install command: $_flag_install_command

Usage: pkgs $_flag_lang [OPTIONS] COMMAND

Commands:
  list          List all packages
  check|full    List packages and check which ones are installed

Options:
  -h, --help    Print this help message and exit
  -e, --emoji   Use emoji in output"
end
