#!/bin/sh
# vim:filetype=bash
# Installs the newest stable CPython as the default python/python3 in
# ~/.local/bin. Runs ahead of the numbered before-scripts because chezmoi needs
# a python3 on PATH to interpret the .py ones.

set -eu

if ! command -v uv >/dev/null 2>&1; then
    echo "uv is not installed, skipping python install" >&2
    exit 0
fi

# uv derives its bin directory from XDG_DATA_HOME; pin it so the interpreter
# always lands on the ~/.local/bin that the rest of this repo puts on PATH.
UV_PYTHON_BIN_DIR="$HOME/.local/bin"
export UV_PYTHON_BIN_DIR

# A bare "cpython" request resolves to the newest stable release and skips
# prereleases, which "uv python list" would otherwise sort to the top.
uv python install cpython --default --force --preview-features python-install-default
