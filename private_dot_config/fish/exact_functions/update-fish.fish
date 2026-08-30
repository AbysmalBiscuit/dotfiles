function update-fish --description 'Builds and installs the latest fish release from source'
    set -l repo https://github.com/fish-shell/fish-shell
    set -l dir $XDG_CACHE_HOME/fish_shell_repo

    # The repo carries non-version tags (official, pre_fishfish, OpenBeta_r1) that
    # sort above the releases under -v:refname, so keep only numeric ones.
    set -l ref (git ls-remote --tags --refs --sort=-v:refname $repo \
        | string replace -rf '.*refs/tags/' '' \
        | string match -r '^\d+\.\d+(?:\.\d+)?$' \
        | head -1)

    if test -z "$ref"
        echo "update-fish: could not resolve a release tag from $repo" >&2
        return 1
    end

    if test -d $dir/.git
        git -C $dir fetch --depth 1 origin tag $ref
        or return
        git -C $dir checkout --force --detach $ref
        or return
    else
        git clone --depth 1 --branch $ref $repo $dir
        or return
    end

    rm -rf $dir/build $dir/target

    RUSTFLAGS="$RUSTFLAGS_RELEASE" cargo install --force --path $dir
end
