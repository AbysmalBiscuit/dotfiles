$SourceDir = "$env:USERPROFILE\.local\share\chezmoi"

Get-Content "$SourceDir\.chezmoiscripts\windows\run_onchange_before_01-generate-has-cache.ps1.tmpl" -Raw | chezmoi execute-template | powershell -Command -
