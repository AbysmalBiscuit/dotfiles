# chezmoi:template:left-delimiter="# {{" right-delimiter="}}"
# some common environment variables to optimise compilation
# export commands that are commented out are the defaults in /etc/makepkg.conf
# To see latest default makepkg.conf:
# https://gitlab.archlinux.org/archlinux/packaging/packages/pacman/-/blob/main/makepkg.conf

# system and architecture
export ARCH='# {{ .arch }}'
export CHOST='# {{ .chost }}'

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
# {{- /* if lookPath "nproc" */}}
# {{- /* $nproc := output "nproc" | trimSuffix "\n" */}}
export MAKEFLAGS="-j# {{ .system.build_jobs }}"

#-- Numpy build flags:
export NPY_NUM_BUILD_JOBS="# {{ .system.build_jobs }}"
# {{- /* end */}}

# rust
# -C link-arg=-z -C link-arg=pack-relative-relocs -C force-frame-pointers=yes
export RUSTFLAGS='-C target-cpu=native'
# {{ if .is_windows -}}
# {{- /* Windows linker doesn't support the linker args */ -}}
export RUSTFLAGS_RELEASE="${RUSTFLAGS} -C opt-level=3 -C debuginfo=none -C debug_assertions=no -C codegen-units=1"
# {{- else -}}
export RUSTFLAGS_RELEASE="${RUSTFLAGS} -C opt-level=3 -C debuginfo=none -C debug_assertions=no -C codegen-units=1 -C link-arg=-z -C link-arg=pack-relative-relocs"
# {{- end }}

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
# {{- if stat (joinPath .chezmoi.homeDir ".config" "chezmoi" "go_level.txt") }}
# export GOAMD64="# {{ include (joinPath .chezmoi.homeDir ".config" "chezmoi" "go_level.txt") | replaceAllRegex "\n" "" }}"
# {{- end }}

# {{- if index .has "sccache" }}
# if [[ -f "$HOME/.cargo/bin/sccache" ]]; then
export SCCACHE_SERVER_PORT="4226"
# export RUSTC_WRAPPER="$HOME/.cargo/bin/sccache"
# export SCCACHE_DIR="$HOME/.cache/sccache"
# export SCCACHE_DIRECT=true
export SCCACHE_CONF="$HOME/.config/sccache/config.toml"
# fi
# {{- end }}

# {{- if index .has "zccache" }}
# Select zccache for Rust builds, overriding Cargo's configured rustc-wrapper.
# export RUSTC_WRAPPER="zccache"

# Limit cached artifacts to 25 GiB, excluding logs and metadata.
export ZCCACHE_CACHE_SIZE_BYTES="26843545600"
# Set the cache budget as a filesystem percentage instead of a byte limit; do not set both.
# export ZCCACHE_CACHE_SIZE_PERCENT="5"
# Override the cache and daemon-state root; share one location across worktrees.
# export ZCCACHE_CACHE_DIR="$HOME/.cache/zccache"
# Remap embedded source paths so equivalent builds can share entries across worktrees.
export ZCCACHE_PATH_REMAP="auto"
# Override the worktree normalization root when Git autodetection is unsuitable.
# export ZCCACHE_WORKTREE_ROOT="$PWD"
# Set compiler scheduling priority: auto, normal, low, idle, or high.
export ZCCACHE_COMPILE_PRIORITY="normal"
# Set link-like work priority separately; it does not inherit the compiler priority override.
export ZCCACHE_COMPILE_PRIORITY_LINK="normal"
# Stop the daemon after this many idle seconds; zero keeps it running.
# export ZCCACHE_IDLE_TIMEOUT_SECS="3600"
# Bypass zccache and run the compiler directly when enabled.
# export ZCCACHE_DISABLE="1"
# Opt into caching Rust test-harness links when enabled.
# export ZCCACHE_CACHE_TEST_BINS="1"
# Run cheap compiler probes directly without a daemon round trip when enabled.
# export ZCCACHE_PROBE_BYPASS="1"
# Select staged output handling: off, rust, c-cpp, exec, or all; unset keeps the default scope.
# export ZCCACHE_STAGED_ARTIFACTS="off"
# Relocate temporary compiler staging separately from durable cache storage.
# export ZCCACHE_STAGING_DIR="$HOME/.cache/zccache-staging"
# Skip C/C++ system-header tracking for speed, risking stale hits after SDK or header updates.
# export ZCCACHE_FAST="1"
# Track system headers for cache invalidation, overriding the fast preset when explicitly set.
# export ZCCACHE_SCAN_SYSTEM_HEADERS="1"
# Validate compiler path spelling: off, consistent, or absolute.
# export ZCCACHE_STRICT_PATHS="off"
# Select a separate daemon identity and mutable state within the shared cache root.
# export ZCCACHE_DAEMON_NAMESPACE="dev"
# Override the daemon IPC endpoint; all clients must use the same endpoint.
# export ZCCACHE_ENDPOINT="$HOME/.cache/zccache/daemon.sock"
# Write an additional size-capped daemon diagnostic log.
# export ZCCACHE_LOG_FILE="$HOME/.cache/zccache/diagnostic.log"
# Limit each diagnostic log file in bytes; one rotated archive is also retained.
# export ZCCACHE_LOG_FILE_MAX_BYTES="16777216"
# Set the compile/link response timeout before daemon recovery; zero disables wedge detection.
# export ZCCACHE_WEDGE_RECV_TIMEOUT_SECS="180"
# Disable the automatic retry after a compile/link transport failure when enabled.
# export ZCCACHE_DISABLE_LINK_RETRY="1"
# Silences zccache info output
export ZCCACHE_QUIET="1"
# {{- end }}
