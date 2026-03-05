function update-fish --description 'Builds and installs fish from source'
    set fish_repo_dir $XDG_CACHE_HOME/fish_shell_repo
    mkdir -p $fish_repo_dir
    cd $fish_repo_dir
    if not test -d $fish_repo_dir
        git clone https://github.com/fish-shell/fish-shell .
    else
        git pull
    end

    if test -d build
        rm -rf build
    end
    if test -d target
        rm -rf target
    end

    RUSTFLAGS="$RUSTFLAGS_RELEASE" cargo install --path .

    # mkdir build
    # cd build
    # cmake .. -DCMAKE_Rust_CARGO_TARGET=release
    # cmake --build .
end
