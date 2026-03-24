$chezmoiDir = chezmoi source-path
$scriptPath = Join-Path $chezmoiDir ".chezmoiscripts\run_onchange_before_01-generate-has-cache.ps1.tmpl"
$tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".ps1")
Get-Content $scriptPath -Raw | chezmoi execute-template | Set-Content $tempFile -Encoding UTF8
& pwsh -NoProfile -NonInteractive -File $tempFile
if (Test-Path $tempFile) { Remove-Item $tempFile }
chezmoi init
