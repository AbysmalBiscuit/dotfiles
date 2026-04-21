$ChezmoiDir = "$env:USERPROFILE\.config\chezmoi"
$SourceDir = "$env:USERPROFILE\.local\share\chezmoi"

# 1. Run first init
chezmoi init

# 2. Get externals
chezmoi apply --include=externals

# 3. Decrypt secret key
Get-Content "$SourceDir\.chezmoiscripts\windows\run_once_decrypt-private-key.ps1.tmpl" -Raw | chezmoi execute-template | powershell -Command -

# 4. Decrypt secrets
age -d -i "$CHEZMOI_KEY" -o "$HOME/.config/chezmoi/secrets.toml" "$SourceDir/secrets.toml.age"

# 5. Run scripts for the firs time to build has cache
chezmoi apply --include=scripts

pwsh -File build_tool_cache.ps1

Get-Content "$SourceDir\.chezmoiscripts\windows\run_once_set-environment-variables.ps1.tmpl" -Raw | chezmoi execute-template | powershell -Command -

# 6. Run second init, chezmoi.toml will now be complete
chezmoi init

# 7. Run regular apply
chezmoi apply
