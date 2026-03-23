# chezmoi:template:left-delimiter="# {{" right-delimiter="}}"
# some common environment variables to optimise compilation
# export commands that are commented out are the defaults in /etc/makepkg.conf
# To see latest default makepkg.conf:
# https://gitlab.archlinux.org/archlinux/packaging/packages/pacman/-/blob/main/makepkg.conf

# system and architecture
ARCH='# {{ .arch | quote }}'
CHOST='# {{ .chost | quote }}'
export ARCH
export CHOST

#-- Compiler and Linker Flags
# -march (or -mcpu) builds exclusively for an architecture
# -mtune optimizes for an architecture, but builds for whole processor family
# export CFLAGS="-march=native -mtune=native -O2 -pipe -fstack-protector-strong -fno-plt"
export CFLAGS="-march=native -O2 -pipe -fno-plt -fexceptions \
        -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security \
        -fstack-clash-protection -fcf-protection \
        -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
# export CFLAGS="-march=native -O2 -pipe -fno-plt -fexceptions \
#         -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security"
export CPPFLAGS="-D_FORTIFY_SOURCE=2"
#export CXXFLAGS="-march=x86-64 -mtune=generic -O3 -pipe -fstack-protector-strong -fno$
export CXXFLAGS="${CFLAGS}"
#export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"

#-- Debugging flags
export DEBUG_CFLAGS="-g -fvar-tracking-assignments"
export DEBUG_CXXFLAGS="-g -fvar-tracking-assignments"

#-- Make Flags: change this for DistCC/SMP systems
MAKEFLAGS="-j$(nproc)"
export MAKEFLAGS

#-- Numpy build flags:
export NPY_NUM_BUILD_JOBS="$(nproc)"

# rust
# -C link-arg=-z -C link-arg=pack-relative-relocs -C force-frame-pointers=yes
export RUSTFLAGS='-C target-cpu=native'
# {{ if .is_windows -}}
# {{- /* Windows linker doesn't support the linker args */ -}}
RUSTFLAGS_RELEASE="${RUSTFLAGS} -C opt-level=3 -C debuginfo=none -C debug_assertions=no -C codegen-units=1"
# {{- else -}}
RUSTFLAGS_RELEASE="${RUSTFLAGS} -C opt-level=3 -C debuginfo=none -C debug_assertions=no -C codegen-units=1 -C link-arg=-z -C link-arg=pack-relative-relocs"
# {{- end }}
export RUSTFLAGS_RELEASE

# {{- if .is_macos }}
# Setting compiler variables for specific libraries
# {{- if stat "/usr/local/opt/openblas" }}
# if [[ -d "/usr/local/opt/openblas" ]]; then
export LDFLAGS="$LDFLAGS -L/usr/local/opt/openblas/lib"
export CPPFLAGS="$CPPFLAGS -I/usr/local/opt/openblas/include"
# fi
# {{- end }}

# {{- if stat "/usr/local/opt/qt" }}
# if [[ -d "/usr/local/opt/qt" ]]; then
export LDFLAGS="$LDFLAGS -L/usr/local/opt/qt/lib"
export CPPFLAGS="$CPPFLAGS -I/usr/local/opt/qt/include"
# fi
# {{- end }}

# {{- if stat "/usr/local/opt/llvm" }}
# if [[ -d "/usr/local/opt/llvm" ]]; then
export LDFLAGS="$LDFLAGS -L/usr/local/opt/llvm/lib"
export CPPFLAGS="$CPPFLAGS -I/usr/local/opt/llvm/include"
# fi
# {{- end }}
# {{- end }}

# go
# {{- if .tool.go }}
# if has_command go; then
GOAMD64="v1"
temp_file=$(mktemp 'XXXXX.go')
printf 'package main\nfunc main() { println("testing go level") }\n' >"$temp_file"

for level in 4 3 2 1; do
    if GO111MODULE=off GOAMD64="v$level" go run "$temp_file" &>/dev/null; then
        GOAMD64="v$level"
        break
    fi
done

# Final cleanup if the loop finishes without success
if [[ -f "$temp_file" ]]; then
    rm "$temp_file"
fi
export GOAMD64
# fi
# {{- end }}

# if [[ -f "$HOME/.cargo/bin/sccache" ]]; then
# export RUSTC_WRAPPER="$HOME/.cargo/bin/sccache"
# export SCCACHE_DIR="$HOME/.cache/sccache"
# export SCCACHE_DIRECT=true
# export SCCACHE_CONF="$HOME/.config/sccache/config.toml"
# fi
