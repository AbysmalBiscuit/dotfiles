#!/bin/sh

chezmoi_dir="$(chezmoi source-path)"
for d in AppData dot_cargo private_dot_config dot_local; do
    fdfind -t f '.*' "$chezmoi_dir/$d" -x chmod 644 '{}'
done

fdfind -t d '.*' "$chezmoi_dir/dot_local" -x chmod 750 '{}'
