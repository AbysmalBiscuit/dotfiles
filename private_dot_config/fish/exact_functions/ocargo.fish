# Defined in - @ line 1
function ocargo --wraps='cargo' --description 'alias ocargo=cargo'
    argparse --ignore-unknown --exclusive f,l --exclusive m,no-mold n/nightly f/fat l/lto d/dylib m/mold no-mold debug h/help -- $argv
    or return

    if set -q _flag_help
        echo "Run cargo with compiler optimizations enabled"
        echo
        echo "Usage: ocargo [OCARGO_OPTS] CARGO_CMD [CARGO_CMD_OPTS]"
        echo
        echo "OCARGO_OPTS:"
        echo "-n, --nightly    Use nightly compiler"
        echo "-f, --fat        Enable fat LTO"
        echo "-l, --lto        Enable thin LTO"
        echo "-d, --dylib      Enable dylib-lto flag"
        echo "-m, --mold       Use mold linker, even if \$MOLD isn't set"
        echo "--no-mold        Don't use mold linker, even if it's available"
        echo "-h, --help       Print help"
        echo "--debug          Print ocargo debug information"
        echo
        echo "Run 'cargo --help' to see help for cargo"
        return
    end

    set -l rust_flags
    if set -q RUSTFLAGS_RELEASE
        set rust_flags $RUSTFLAGS_RELEASE
    else if set -q RUSTFLAGS
        set rust_flags $RUSTFLAGS
    end

    # set initial_rust_flags
    if set -q rust_flags[1]
        # set rust_flags $RUSTFLAGS
        # set initial_rust_flags $RUSTFLAGS
        if not string match -q -- "*target-cpu*" $rust_flags
            set --append rust_flags "-C target-cpu=native"
        end
        if not string match -q -- "*opt-level=3*" $rust_flags
            set --append rust_flags "-C opt-level=3"
        end
        if not string match -q -- "*debuginfo*" $rust_flags
            set --append rust_flags "-C debuginfo=none"
        end
        if not string match -q -- "*debug_assertions*" $rust_flags
            set --append rust_flags "-C debug_assertions=no"
        end
        if not string match -q -- "*codegen-units*" $rust_flags
            set --append rust_flags "-C codegen-units=1"
        end
    else
        set rust_flags "-C target-cpu=native -C opt-level=3 -C debuginfo=none -C debug_assertions=no -C codegen-units=1"
    end

    # set -gx CARGO_PROFILE_RELEASE_CODEGEN_UNITS 1
    if type -q mold && set -q _flag_mold && not set -q _flag_no_mold && begin
            set -q MOLD || set -q _flag_mold
        end
        if not set -q MOLD
            set MOLD ()
        end
        set --append rust_flags "-C link-arg=-fuse-ld=$MOLD"
    end

    if set -q _flag_lto
        set --append rust_flags "-C lto=thin -C embed-bitcode=yes"
        # set -gx CARGO_PROFILE_RELEASE_LTO thin
    end

    if set -q _flag_fat
        set --append rust_flags "-C lto=fat -C embed-bitcode=yes"
        # set -gx CARGO_PROFILE_RELEASE_LTO fat
    end

    if set -q _flag_nightly
        if test $HAS_NIGHTLY_RUST = true
            set --prepend argv "+nightly"
        else
            echo "nightly rust is not available. to install it run:"
            echo "rustup toolchain install nightly"
            return
        end
    end

    if set -q _flag_nightly; and set -q _flag_dylib
        set --append rust_flags -Zdylib-lto
    end

    # set -gx RUSTFLAGS "$rust_flags"
    if set -q _flag_debug
        echo "ocargo debug information:"
        echo "RUSTFLAGS='$rust_flags'"
        # echo "CARGO_PROFILE_RELEASE_LTO='$CARGO_PROFILE_RELEASE_LTO'"
        # echo "CARGO_PROFILE_RELEASE_CODEGEN_UNITS='$CARGO_PROFILE_RELEASE_CODEGEN_UNITS'"
        echo cargo $argv
        return
    end

    # echo RUSTFLAGS="'$rust_flags'" cargo $argv
    RUSTFLAGS="$rust_flags" cargo $argv

    # set -gx RUSTFLAGS $initial_rust_flags
end
