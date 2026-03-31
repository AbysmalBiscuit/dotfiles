Get-Content "$(chezmoi source-path)/edit_secrets.ps1.tmpl" -Raw | chezmoi execute-template | Out-String | Invoke-Expression
chezmoi init
