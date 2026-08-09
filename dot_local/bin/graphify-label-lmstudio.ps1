#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Label graphify communities using a local LM Studio model.

.DESCRIPTION
    Runs `graphify label` against the graph in the current project, routed
    through LM Studio's OpenAI-compatible server. Prepares everything the run
    needs first: the custom provider entry in ~/.graphify/providers.json, the
    API-key env var, a running server, and a loaded model. Batch size is derived
    from the model's loaded context length and concurrency from its parallel-slot
    count, so the prompt cannot overflow the window.

.PARAMETER Path
    Project root containing graphify-out/graph.json. Defaults to the current
    directory.

.PARAMETER Model
    LM Studio model key. Defaults to the loaded model, else the provider's
    default_model, else the only downloaded LLM.

.PARAMETER BatchSize
    Communities per LLM call. Derived from the context window when omitted.

.PARAMETER Concurrency
    Parallel labeling calls. Defaults to the model's parallel-slot count.

.PARAMETER ContextLength
    Context length to load the model with, when it is not already loaded.

.PARAMETER MissingOnly
    Keep existing labels; only name missing or placeholder communities.

.PARAMETER NoViz
    Skip graph.html regeneration.

.PARAMETER DryRun
    Print the resolved graphify command without running it.

.EXAMPLE
    graphify-label-lmstudio.ps1

.EXAMPLE
    graphify-label-lmstudio.ps1 -Path ../other-project -MissingOnly

.EXAMPLE
    graphify-label-lmstudio.ps1 -ContextLength 32768 -Model qwen2.5-coder-7b-instruct
#>

[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [string] $Model,
    [int]    $BatchSize = 0,
    [int]    $Concurrency = 0,
    [int]    $ContextLength = 0,
    [string] $Backend = 'lmstudio',
    [int]    $Port = 1234,
    [switch] $MissingOnly,
    [switch] $NoViz,
    [switch] $DryRun,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Rest
)

$ErrorActionPreference = 'Stop'

# Output budget the provider reserves for the model's reply, and the observed
# prompt cost of one community (top_k node labels plus its god-node hints).
# Batch size falls out of what is left of the context window.
$OutputReserve = 2048
$PromptOverhead = 512
$TokensPerCommunity = 280

$ProvidersPath = Join-Path $HOME '.graphify/providers.json'
$ApiKeyVar = 'LMSTUDIO_API_KEY'
$BaseUrl = "http://localhost:$Port/v1"

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string] $Message) Write-Host "    $Message" -ForegroundColor DarkGray }

function Get-LoadedModels {
    $raw = & lms ps --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try { return @($raw | ConvertFrom-Json) } catch { return @() }
}

function Get-DownloadedLlmKeys {
    $raw = & lms ls --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try { return @($raw | ConvertFrom-Json | Where-Object { $_.type -eq 'llm' } | ForEach-Object { $_.modelKey }) }
    catch { return @() }
}

$graphPath = Join-Path $Path 'graphify-out/graph.json'
if (-not (Test-Path $graphPath)) {
    throw "No graph found at $graphPath. Run /graphify (or `graphify extract`) on this project first."
}
if (-not (Get-Command lms -ErrorAction SilentlyContinue)) {
    throw "LM Studio CLI 'lms' not on PATH. Install LM Studio, then run: lms bootstrap"
}
if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
    throw "'graphify' not on PATH. Install with: uv tool install 'graphifyy[openai]'"
}

Write-Step "Project: $Path"

# --- provider entry -------------------------------------------------------
$providers = @{}
if (Test-Path $ProvidersPath) {
    $providers = Get-Content $ProvidersPath -Raw | ConvertFrom-Json -AsHashtable
}
$providerModel = if ($providers.ContainsKey($Backend)) { $providers[$Backend].default_model } else { $null }

if (-not $Model) {
    $loaded = Get-LoadedModels | Where-Object { $_.type -eq 'llm' } | Select-Object -First 1
    $Model = if ($loaded) { $loaded.identifier }
             elseif ($providerModel) { $providerModel }
             else { Get-DownloadedLlmKeys | Select-Object -First 1 }
}
if (-not $Model) { throw "No LM Studio LLM found. Download one, or pass -Model <key>." }

if (-not $providers.ContainsKey($Backend)) {
    Write-Step "Registering provider '$Backend' in $ProvidersPath"
    $providers[$Backend] = [ordered]@{
        base_url              = $BaseUrl
        default_model         = $Model
        env_key               = $ApiKeyVar
        model_env_key         = 'GRAPHIFY_LMSTUDIO_MODEL'
        temperature           = 0
        max_completion_tokens = $OutputReserve
        pricing               = @{ input = 0.0; output = 0.0 }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $ProvidersPath) | Out-Null
    $providers | ConvertTo-Json -Depth 5 | Set-Content $ProvidersPath -Encoding utf8
}

# graphify reads the provider's env_key; any non-empty value satisfies the
# OpenAI client, which requires a key even against a local server.
$keyName = if ($providers[$Backend].env_key) { $providers[$Backend].env_key } else { $ApiKeyVar }
if (-not [Environment]::GetEnvironmentVariable($keyName)) {
    Set-Item "env:$keyName" 'lm-studio'
    Write-Note "$keyName was unset; using a placeholder for this run"
}

# --- server ---------------------------------------------------------------
# -DryRun resolves the command without touching LM Studio, so it reports what
# an already-loaded model would give and falls back to defaults otherwise.
if (-not $DryRun) {
    try {
        Invoke-RestMethod "$BaseUrl/models" -TimeoutSec 4 | Out-Null
    }
    catch {
        Write-Step "Starting LM Studio server on port $Port"
        & lms server start --port $Port | Where-Object { $_ } | Write-Note
        Invoke-RestMethod "$BaseUrl/models" -TimeoutSec 15 | Out-Null
    }
}

# --- model ----------------------------------------------------------------
$loaded = Get-LoadedModels | Where-Object { $_.identifier -eq $Model } | Select-Object -First 1
if (-not $loaded -and -not $DryRun) {
    Write-Step "Loading $Model"
    $loadArgs = @($Model, '-y', '--gpu', 'max')
    if ($ContextLength -gt 0) { $loadArgs += @('-c', "$ContextLength") }
    & lms load @loadArgs | Where-Object { $_ } | Write-Note
    $loaded = Get-LoadedModels | Where-Object { $_.identifier -eq $Model } | Select-Object -First 1
    if (-not $loaded) { throw "Failed to load $Model." }
}
elseif ($loaded -and $ContextLength -gt 0 -and $loaded.contextLength -ne $ContextLength) {
    Write-Note "$Model is loaded at $($loaded.contextLength) context, not the requested $ContextLength; reload it with: lms unload $Model; lms load $Model -c $ContextLength"
}

$ctx = if ($loaded) { [int] $loaded.contextLength } elseif ($ContextLength -gt 0) { $ContextLength } else { 8192 }
$slots = if ($loaded) { [Math]::Max(1, [int] $loaded.parallel) } else { 4 }
if ($Concurrency -le 0) { $Concurrency = $slots }
if ($BatchSize -le 0) {
    $usable = $ctx - $OutputReserve - $PromptOverhead
    $BatchSize = [Math]::Floor($usable / $TokensPerCommunity)
    $BatchSize = [Math]::Min(100, [Math]::Max(4, $BatchSize))
}
Write-Note "$Model - ${ctx}-token context, $slots parallel slot(s)"
Write-Note "batch-size $BatchSize, max-concurrency $Concurrency"

# --- run ------------------------------------------------------------------
$labelsPath = Join-Path $Path 'graphify-out/.graphify_labels.json'
$before = if (Test-Path $labelsPath) { (Get-Content $labelsPath -Raw | ConvertFrom-Json).PSObject.Properties.Name.Count } else { 0 }
if ($before -gt 0 -and -not $MissingOnly) {
    Write-Note "$before existing labels will be replaced (graphify backs up graphify-out/ to a dated folder first; -MissingOnly keeps them)"
}

$graphifyArgs = @(
    'label', $Path,
    '--backend', $Backend,
    '--model', $Model,
    '--batch-size', "$BatchSize",
    '--max-concurrency', "$Concurrency"
)
if ($MissingOnly) { $graphifyArgs += '--missing-only' }
if ($NoViz) { $graphifyArgs += '--no-viz' }
if ($Rest) { $graphifyArgs += $Rest }

if ($DryRun) {
    Write-Host "graphify $($graphifyArgs -join ' ')"
    return
}

Write-Step "graphify $($graphifyArgs -join ' ')"
$started = Get-Date
& graphify @graphifyArgs
$exit = $LASTEXITCODE
$elapsed = (Get-Date) - $started

if ($exit -ne 0) {
    Write-Host "graphify label failed (exit $exit) after $([Math]::Round($elapsed.TotalMinutes, 1)) min" -ForegroundColor Red
    exit $exit
}

# --- verify ---------------------------------------------------------------
Write-Step "Done in $([Math]::Round($elapsed.TotalMinutes, 1)) min"
if (Test-Path $labelsPath) {
    $names = (Get-Content $labelsPath -Raw | ConvertFrom-Json).PSObject.Properties.Value
    $placeholders = @($names | Where-Object { $_ -match '^Community \d+$' }).Count
    $distinct = ($names | Sort-Object -Unique).Count
    Write-Note "$($names.Count) labels, $distinct distinct, $placeholders placeholder(s)"
    if ($placeholders -gt 0) {
        Write-Host "    $placeholders communities kept 'Community N' - the model overflowed context or returned unparseable JSON. Retry those with: $($MyInvocation.MyCommand.Name) -MissingOnly -BatchSize $([Math]::Max(4, [Math]::Floor($BatchSize / 2)))" -ForegroundColor Yellow
    }
}
