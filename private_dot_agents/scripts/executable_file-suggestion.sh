#!/bin/bash
# Entry point for the @ file-path autocomplete. Claude Code's
# `fileSuggestion.command` in settings.json points here; the matching and
# ranking live in file-suggestion.ts beside this file.
self=${BASH_SOURCE[0]}
dir=${self%/*}
[[ $dir == "$self" ]] && dir=.
exec bun "$dir/file-suggestion.ts"
