#!/bin/sh

CHEZMOI_DIR="$HOME/.config/chezmoi"
SOURCE_DIR="$HOME/.local/share/chezmoi"
CHEZMOI_KEY="$CHEZMOI_DIR/key.txt"

# 1. Decrypt secret key
if [ ! -f "$HOME/.config/chezmoi/key.txt" ]; then
    mkdir -p "$CHEZMOI_DIR"
    chezmoi age decrypt --output "$CHEZMOI_DIR/key.txt" --passphrase "$SOURCE_DIR/key.txt.age"
    chmod 600 "$CHEZMOI_KEY"
fi

# 2. Run first init
chezmoi init

# 3. Get externals
chezmoi apply --include=externals

# 4. Decrypt secrets
age -d -i "$CHEZMOI_KEY" -o "$HOME/.config/chezmoi/secrets.toml" "$SOURCE_DIR/secrets.toml.age"

# 5. Run scripts for the firs time to build has cache
chezmoi apply --include=scripts

# 6. Run second init, chezmoi.toml will now be complete
chezmoi init

# 7. Run regular apply
chezmoi apply
