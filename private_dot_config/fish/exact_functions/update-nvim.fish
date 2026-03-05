function update-nvim --description 'Updates a nightly neovim install'
    switch "$OS"
        case wsl linux
            set -l bin_dir $HOME/.local/bin
            mkdir -p $bin_dir
            cd $bin_dir || exit 1
            if test -d $bin_dir/squashfs-root
                if test -x $bin_dir/squashfs-root/usr/bin/nvim
                    rm -rf $bin_dir/squashfs-root
                else
                    echo "Error: '$HOME/.local/bin/squashfs-root' already exists, will not be able to extract neovim appimage."
                    echo "Check manually"
                    return 1
                end
            end
            set arch $(uname -m)
            set appimage $bin_dir/nvim.appimage
            echo "Downloading neovim appimage"
            wget -O $appimage https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-$arch.appimage
            # Check checksum
            set -l checksum (curl -s https://api.github.com/repos/neovim/neovim/releases/tags/nightly | jq ".assets[] | select(.name == 'nvim-linux-$arch.appimage') | .digest" | string replace -r '"sha256:(.+)"' '$1' | string trim)
            if set -q checksum[1]
                echo "Veryfying checksum"
                set -l dl_checksum (sha256sum $appimage | string replace -r '^(.+) .+$' '$1' | string trim)
                if test "$checksum" != "$dl_checksum"
                    echo "Error: Checksums do not match!"
                    echo "Fetched: $checksum"
                    echo "Calculated: $dl_checksum"
                    echo "Verify manualy"
                    exit 1
                end
                echo "Checksums match"
            else
                echo "Warning: No checksums found, proceeding with update"
            end
            chmod u+x $appimage
            set -l nvim_squashfs $bin_dir/nvim-squashfs-root
            if test -d $nvim_squashfs
                rm -rf $nvim_squashfs
            end
            $appimage --appimage-extract
            mv $bin_dir/squashfs-root $nvim_squashfs
            rm $appimage $bin_dir/nvim
            ln -s $bin_dir/nvim-squashfs-root/usr/bin/nvim $bin_dir/nvim
            chmod -R go-rwx $bin_dir/nvim $nvim_squashfs
    end
end
