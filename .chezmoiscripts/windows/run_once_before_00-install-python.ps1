# vim:filetype=ps1
# Installs the newest stable CPython as the default python.exe/python3.exe in
# ~/.local/bin. Runs ahead of the numbered before-scripts because chezmoi needs
# a python3 on PATH to interpret the .py ones.

$ErrorActionPreference = "Stop"

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Warning "uv is not installed, skipping python install"
    exit 0
}

# uv derives its bin directory from XDG_DATA_HOME; pin it so the interpreter
# always lands on the ~/.local/bin that the rest of this repo puts on PATH.
$env:UV_PYTHON_BIN_DIR = Join-Path $HOME ".local\bin"

# A bare "cpython" request resolves to the newest stable release and skips
# prereleases, which "uv python list" would otherwise sort to the top.
uv python install cpython --default --force --preview-features python-install-default
exit $LASTEXITCODE
