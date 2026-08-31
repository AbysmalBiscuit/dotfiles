#!/usr/bin/env bash
# Rebuild the shell completions cache by rendering and running the chezmoi
# script that normally does it on `chezmoi apply`.

set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$source_dir/.chezmoiscripts/run_onchange_after_90-generate-shell-completions.sh.tmpl"

if [ ! -f "$template" ]; then
    printf 'Template not found: %s\n' "$template" >&2
    exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
    printf 'chezmoi is not on PATH\n' >&2
    exit 1
fi

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

chezmoi execute-template <"$template" >"$rendered"
bash "$rendered"
chezmoi init
