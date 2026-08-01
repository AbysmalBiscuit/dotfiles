#!/bin/sh

chezmoi_dir="$(chezmoi source-path)"
script_path="$chezmoi_dir/.chezmoiscripts/run_onchange_before_01-generate-has-cache.sh.tmpl"

temp_file="$(mktemp --tmpdir='/tmp' XXXXXX.sh)"
cat "$script_path" | chezmoi execute-template >"$temp_file"

"$SHELL" "$temp_file"

if test -f "$temp_file"; then
    rm "$temp_file"
fi
chezmoi init
