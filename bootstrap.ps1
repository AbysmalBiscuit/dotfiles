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

# 5. Install python, the .py scripts have no interpreter without it
powershell -ExecutionPolicy Bypass -File "$SourceDir\.chezmoiscripts\windows\run_once_before_00-install-python.ps1"

# 6. Build the has cache and re-init, so the py interpreter is set before any .py script runs
pwsh -File build_tool_cache.ps1

# 7. Run scripts for the firs time
chezmoi apply --include=scripts

Get-Content "$SourceDir\.chezmoiscripts\windows\run_once_set-environment-variables.ps1.tmpl" -Raw | chezmoi execute-template | powershell -Command -

# 8. Run second init, chezmoi.toml will now be complete
chezmoi init

# 9. Run regular apply
chezmoi apply
