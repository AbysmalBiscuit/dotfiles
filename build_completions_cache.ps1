#!/usr/bin/env pwsh
# Rebuild the shell completions cache by rendering and running the chezmoi
# script that normally does it on `chezmoi apply`.

$ErrorActionPreference = 'Stop'

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$template = Join-Path $sourceDir '.chezmoiscripts/windows/run_onchange_after_90-generate-shell-completions.ps1.tmpl'

if (-not (Test-Path $template)) {
    throw "Template not found: $template"
}

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
    throw 'chezmoi is not on PATH'
}

$rendered = Get-Content -Raw -LiteralPath $template | chezmoi execute-template
if ($LASTEXITCODE -ne 0) {
    throw "chezmoi execute-template failed with exit code $LASTEXITCODE"
}

& ([scriptblock]::Create($rendered))
chezmoi init
