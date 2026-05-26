#!/bin/sh
chezmoi execute-template "$(cat "$(chezmoi source-path)/edit_secrets.sh.tmpl")" | sh
chezmoi init
