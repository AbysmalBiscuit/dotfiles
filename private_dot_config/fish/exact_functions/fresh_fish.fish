function fresh_fish --description "Generate completions and other useful items on demand"
    echo "Fishing..."
    set -l _FISH_CACHE_COMPLETIONS_DIR $__fish_cache_dir/completions
    set -l session_file "/tmp/fish-session-$USER"
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
    set -x fish_update_completions_detach true
    fish_update_completions
    set -u fish_update_completions_detach

    function _safe_rm
        if test -f $argv[1]
            rm $argv[1]
        end
    end

    function _append_to_fresh_fish_env --description 'Appends variable declarations to the cached environment variable file.'
        echo "$argv[1] $argv[2..-1]" >>$fresh_fish_env
    end

    if test -f $fresh_fish_env
        echo "" >$fresh_fish_env
    end

    # Configure environment variables
    if set -q EDITOR; and string match --quiet --regex '^.*nvim(\.exe)?$' $EDITOR
        _append_to_fresh_fish_env "set -gx _EDITOR" $EDITOR
    end

    if not set -q OS
        set -l OS (uname -s | string lower)
        _append_to_fresh_fish_env 'set -gx OS' $OS
    end

    if type -q go
        if not test -f $__fish_cache_dir/go_max_level
            get-max-go-level >$__fish_cache_dir/go_max_level
        end
        _append_to_fresh_fish_env 'set -gx GOAMD64' v(cat $__fish_cache_dir/go_max_level)
    end

    if not set -q PYTHON3_HOST_PROG
        if type -q python3
            _append_to_fresh_fish_env 'set -gx PYTHON3_HOST_PROG' (command -v python3)
        else if type -q python; and command python --version 2>/dev/null | string lower | string match -q -r '.*\b3\.\d+'
            _append_to_fresh_fish_env 'set -gx PYTHON3_HOST_PROG' (command -v python)
        end
    end

    if set -q WSL_DISTRO_NAME
        if not set -q YAZI_WINDOWS_EXECUTABLE
            set -l yazi_exe (command -v yazi.exe)
            if set -q yazi_exe[1]
                _append_to_fresh_fish_env "set -gx YAZI_WINDOWS_EXECUTABLE" "$yazi_exe"
            end
        end
    end

    # Configure Nextcloud dirs
    set -l nextcloud_dir
    switch (uname | string lower)
        case linux
            if set -q WSL_DISTRO_NAME
                set nextcloud_dir (fd -t d -d 2 'Nextcloud' '/mnt/c/Users')
            else
                set nextcloud_dir (fd -t d -d 1 'Nextcloud' "$HOME")
            end
        case darwin
            set nextcloud_dir (fd -t d -d 1 'Nextcloud' "$HOME")
    end

    if set -q nextcloud_dir[1]
        set nextcloud_dir (string replace --regex '(.+)/$' '$1' "$nextcloud_dir")
        _append_to_fresh_fish_env 'set -gx NC_DIR' "$nextcloud_dir"
        _append_to_fresh_fish_env 'set -gx NC_SETTINGS' "$nextcloud_dir/settings-files"
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

    # Configure macOS paths
    if string match -q -r 'Darwin.*' (uname -s)
        if test -d "/Users/admin/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-4.1.7-2022-11-21-562b8a195/bin"
            set --append fish_user_paths "/Users/admin/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-4.1.7-2022-11-21-562b8a195/bin"
        end

        if test -d "/Users/admin/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-4.0.4-2021-07-01-9df386fcd/bin"
            set --append fish_user_paths "/Users/admin/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-4.0.4-2021-07-01-9df386fcd/bin"
        end

        # Ensure GNU binaries are prioritized
        if test -d /usr/local/lib/gnubin
            set --prepend fish_user_paths /usr/local/lib/gnubin
        end

        if test -d /usr/local/opt/make/libexec/gnubin
            set --prepend fish_user_paths /usr/local/opt/make/libexec/gnubin
        end

        if test -d /usr/local/opt/uutils-coreutils/libexec/uubin
            set --prepend fish_user_paths /usr/local/opt/uutils-coreutils/libexec/uubin
        end

        echo "Caught the macOS environment"
    end

    # Set rust related variables
    if test -d $HOME/.cargo; and command -q rustup
        if test -d $HOME/.cargo/registry/src
            set cargo_src_completions (fd --print0 --type f -E '*zellij*' --full-path '.*completions?/.*\.fish$' "$HOME/.cargo/registry/src" | string split0)

            set final_cargo_completions
            for comp in $cargo_src_completions
                if not contains (basename --suffix=".fish" $comp) $all_completions
                    set --append final_cargo_completions $comp
                end
            end

            if test (count $final_cargo_completions) -ge 1
                _append_to_fresh_fish_env "set -gx _CARGO_COMPLETION_PATHS" $final_cargo_completions
            end
        end

        _append_to_fresh_fish_env "set -gx CLIPPY_CONF_DIR" "$HOME/.config/clippy"

        if test -f "$HOME/.cargo/bin/sccache"
            _append_to_fresh_fish_env "set -gx RUSTC_WRAPPER" "$HOME/.cargo/bin/sccache"
            _append_to_fresh_fish_env "set -gx SCCACHE_DIR" "$HOME/.cache/sccache"
            _append_to_fresh_fish_env "set -gx SCCACHE_DIRECT true"
            _append_to_fresh_fish_env "set -gx SCCACHE_CONF" "$HOME/.config/sccache/config.toml"
        end

        _append_to_fresh_fish_env "set -gx HAS_NIGHTLY_RUST" (rustup toolchain list | string match -q '*nightly*'; and echo -n 1; or echo -n 0)
        _append_to_fresh_fish_env "set -gx HAS_OCARGO" 1

        echo "Caught all the rust environment"
    end

    # nvim environment variables
    if not set -q PATH_CLEAN; and type -q wslinfo
        _append_to_fresh_fish_env "set -gx PATH_CLEAN" (string match --invert --regex '/mnt/[a-z]' $PATH)
    end

    _append_to_fresh_fish_env "set -gx NVIM_EXECUTABLE" (command -v nvim)

    # Python environment variables
    set NUMBA_CACHE_DIR "$HOME/.cache/numba"
    mkdir -p $NUMBA_CACHE_DIR
    _append_to_fresh_fish_env "set -gx NUMBA_CACHE_DIR" "$HOME/.cache/numba"

    echo "Caught all the environment variables"

    # Generate CLI completion for various programs
    for pkg_info in (tail -n +2 $__fish_config_dir/pkgs.csv)
        if string match -q --regex '^\s*#.+' $pkg_info
            continue
        end

        # It's possible to at least get the package name, install command, and completions command
        set -l pkg (__split_pkg $pkg_info)
        # if not string match starship $pkg[2]
        #     continue
        # end
        # echo $pkg
        # return 0
        # set -l lang $pkg[1]
        set -l name $pkg[2]
        # # offset is for this: `,,"` + 1 for 1-index
        # set -l description_start_offset 4
        # set -l description_start (math (string length $lang) + (string length $name) + $description_start_offset)
        # # offset is for this: `,"","","",""`
        # set -l description_end_offset 5
        # set -l description_end (math (string length $argv) - (string length "$pkg[-4]""$pkg[-3]""$pkg[-2]""$pkg[-1]") - $description_end_offset)
        # set -l description (string sub --start $description_start --end $description_end $argv)
        # set -l website (string sub --start 2 --end -1 "$pkg[-4]")
        # set -l git (string sub --start 2 --end -1 "$pkg[-3]")
        # set -l install_command (string sub --start 2 --end -1 "$pkg[-2]")
        # set -l completions_command (string sub --start 2 --end -1 $pkg[-1])
        set -l completions_command $pkg[-2]
        set -l init_command $pkg[-1]
        if type -q $name
            if test -n "$completions_command"
                eval "$completions_command" >$_FISH_CACHE_COMPLETIONS_DIR/$name.fish
                # set -l comp_command (string split ' ' "$completions_command")
                # echo $comp_command
                # $comp_command
                # $comp_command >$_FISH_CACHE_COMPLETIONS_DIR/$name.fish

            end
            if test -n "$init_command"
                eval "$init_command" >>$fresh_fish_env
                # if string match -q '*;*' "$init_command"
                #     for sub_com in (string split ';' "$init_command" | string trim)
                #         set -l init_com (string split ' ' "$sub_com")
                #         # echo $sub_com
                #         # echo $init_com
                #         $init_com >>$fresh_fish_env
                #     end
                # else
                #     set -l init_com (string split ' ' "$init_command")
                #     $init_com >>$fresh_fish_env
                # end
            end
        end
    end

    # if type -q starship
    #     _append_to_fresh_fish_env enable_transience
    # end

    # if type -q mlr
    #     # More robust way of reading the csv using miller
    #     mlr --csv --ho --otsv cat $__fish_config_dir/pkgs.csv | while read -l -d \t lang name desc url git install_command completions_command
    #         set -l comp_command (string split ' ' "$completions_command")
    #         if type -q $name; and test -n "$comp_command"
    #             # echo $comp_command
    #             $comp_command >$_FISH_CACHE_COMPLETIONS_DIR/$name.fish
    #         end
    #     end
    # else
    #     for pkg_info in (cat $__fish_config_dir/pkgs.csv)
    #         # It's possible to at least get the package name, install command, and completions command
    #         set -l pkg (string split ',' $argv)
    #         # set -l lang $pkg[1]
    #         set -l name $pkg[2]
    #         # # offset is for this: `,,"` + 1 for 1-index
    #         # set -l description_start_offset 4
    #         # set -l description_start (math (string length $lang) + (string length $name) + $description_start_offset)
    #         # # offset is for this: `,"","","",""`
    #         # set -l description_end_offset 5
    #         # set -l description_end (math (string length $argv) - (string length "$pkg[-4]""$pkg[-3]""$pkg[-2]""$pkg[-1]") - $description_end_offset)
    #         # set -l description (string sub --start $description_start --end $description_end $argv)
    #         # set -l website (string sub --start 2 --end -1 "$pkg[-4]")
    #         # set -l git (string sub --start 2 --end -1 "$pkg[-3]")
    #         # set -l install_command (string sub --start 2 --end -1 "$pkg[-2]")
    #         set -l completions_command (string sub --start 2 --end -1 $pkg[-1])
    #         set -l comp_command (string split ' ' "$completions_command")
    #         if type -q $name; and test -n "$comp_command"
    #             # echo $comp_command
    #             $comp_command >$_FISH_CACHE_COMPLETIONS_DIR/$name.fish
    #         end
    #     end
    # end

    if type -q eza
        _append_to_fresh_fish_env "set -gx EZA_CONFIG_DIR" "$HOME/.config/eza"
    end

    # Only try to generate fish-lsp completions if not running on first startup.
    # Otherwise the process hangs.
    if type -q fish-lsp; and test -f $session_file
        fish-lsp complete >$_FISH_CACHE_COMPLETIONS_DIR/fish-lsp.fish
    end

    if type -q fzf
        _append_to_fresh_fish_env "set -gx FZF_DEFAULT_OPTS" '"--color=bg+:#313244,bg:#1E1E2E,spinner:#F5E0DC,hl:#F38BA8\
    --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC\
    --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8\
    --color=selected-bg:#45475A\
    --color=border:#6C7086,label:#CDD6F4"'
    end

    # if type -q sk
    #     # "--color=fg:#CDD6F4,bg:#1E1E2E,matched:#45475A,matched_bg:,current:,current_bg:#313244,current_match:,current_match_bg:,spinner:,info:,prompt:,cursor:,selected:,header:,border:"
    #     # "--color=fg:#cdd6f4,bg:#1e1e2e,matched:#313244,matched_bg:#f2cdcd,current:#cdd6f4,current_bg:#45475a,current_match:#1e1e2e,current_match_bg:#f5e0dc,spinner:#a6e3a1,info:#cba6f7,prompt:#89b4fa,cursor:#f38ba8,selected:#eba0ac,header:#94e2d5,border:#6c7086"
    # end

    # Set bindings for shell
    if type -q sk
        # - $SKIM_TMUX_OPTS
        # - $SKIM_CTRL_T_COMMAND
        # - $SKIM_CTRL_T_OPTS
        # - $SKIM_CTRL_R_OPTS
        # - $SKIM_ALT_C_COMMAND
        # - $SKIM_ALT_C_OPTS
        # - $SKIM_COMPLETION_TRIGGER (default: '**')
        # - $SKIM_COMPLETION_OPTS    (default: empty)
        set -l bindings (sk --shell fish --shell-bindings)
        set -l start_idx (math (contains -i 'function skim_key_bindings' $bindings)" + 1")
        set -l last_idx (math (count $bindings)" - 1")
        if not test $bindings[$last_idx] = end
            echo "Error: cannot cleanly extract skim bindings set up function. Check if indices need to be updated in fresh_fish"
            echo "Falling back to normal approach."
            set -a bindings skim_key_bindings
            printf '%s\n' $bindings >>"$fresh_fish_env"
        else
            set -l before_last_idx (math "$last_idx - 1")
            printf '%s\n' $bindings[$start_idx..$before_last_idx] | string replace '  ' '' >>"$fresh_fish_env"
        end
        _append_to_fresh_fish_env "set -gx SK_EXECUTABLE" (command -v sk)
    else if type -q fzf
        # - $FZF_TMUX_OPTS
        # - $FZF_CTRL_T_COMMAND
        # - $FZF_CTRL_T_OPTS
        # - $FZF_CTRL_R_COMMAND
        # - $FZF_CTRL_R_OPTS
        # - $FZF_ALT_C_COMMAND
        # - $FZF_ALT_C_OPTS
        set -l bindings (fzf --fish)
        set -l start_idx (math (contains -i 'function fzf_key_bindings' $bindings)" + 1")
        set -l last_idx (math (count $bindings)" - 2")
        if not test $bindings[$last_idx] = end
            echo "Error: cannot cleanly extract fzf bindings set up function. Check if indices need to be updated in fresh_fish"
            echo "Falling back to normal approach."
            printf '%s\n' $bindings >>"$fresh_fish_env"
        else
            set -l before_last_idx (math "$last_idx - 1")
            printf '%s\n' $bindings[$start_idx..$before_last_idx] | string replace '  ' '' >>"$fresh_fish_env"
        end
    end

    echo "Caught all the completions and commands"

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

        # set --append argc_scripts 7z 7za 7zr ab ant apachectl apropos ar autoconf awk base64 basename basenc bash bc bison brew brotli bundle bunzip2 bzcat bzip2 c++ cat cc certtool chgrp chmod chown chroot cksum clang++ clang cmake code column comm cp cpio crontab csplit curl cut cwebp date dc dd df diff diff3 dig dir dircolors direnv dirname docker-compose docker dos2unix du ed egrep env expand fc-cache fc-cat fc-list fd ffmpeg fgrep file find fish flac flex fmt fold fzf g++ gawk gcc gem gio git gnutls-cli gnutls-serv gpg-agent gpg grep groups gs gsettings gunzip gzip hashcat head hexdump hostname hugo hunspell iconv id install ip jar java jj join jq keepassxc-cli keytool kill killall kubectl less link lldb ln locale locate lp ls lsof lua lzcat lzma m4 magick make man md5sum mkdir mkfifo mknod mktemp mpv mv nano nc ncat nice nl nm nmap node nohup npm npx numfmt nvim objdump od openssl pandoc paste patch pathchk perl pgrep php pinky pip pip3 pipenv pipx pkg-config pkill plutil poetry pr printenv ps ptx pv pwd python3 rake readlink realpath rga rm rmdir rsync ruby scons scp screen sd sed seq sftp sh sha1sum sha256sum sha512sum shar shasum shellcheck shred shuf sk sort source-highlight split sqlite3 ssh-agent ssh-copy-id ssh-keygen ssh stat stdbuf strings strip stty sudo sum svn swift sync sysctl tac tail tailspin tar tcpdump tcsh tee tesseract tex tidy time timeout tmux top touch tput tr truncate tshark tty uname unexpand uniq unix2dos unlink unlzma unxz unzip uptime vale vdir vi vim vimdiff visudo vlc w watch watchgnupg wc wdiff wget whatis which who whois wireshark xargs xxd xxh128sum xxh32sum xxh64sum xxhsum xz xzcat yq yt-dlp zcat zip zipcloak
        argc --argc-completions fish $argc_scripts >$_FISH_CACHE_COMPLETIONS_DIR/from_argc.fish

        echo "Caught all the argc completions"
    end

    _append_to_fresh_fish_env "set -gx fish_user_paths" $fish_user_paths

    date +%s >$__fish_cache_dir/last_fish
end

if [ "$argv[1]" = runme ]
    fresh_fish
end
