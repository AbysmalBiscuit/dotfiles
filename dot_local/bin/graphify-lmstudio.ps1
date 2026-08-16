#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Bring a project's graphify graph up to date using a local LM Studio model.

.DESCRIPTION
    Runs graphify's three refresh steps in order, routed through LM Studio's
    OpenAI-compatible server:

      update  re-extract changed code through graphify's AST extractors (no LLM)
      docs    send new or changed docs, papers and images to the model
      label   name any community that is missing a name or still a placeholder

    With no arguments it runs all three. Name one or more phases to run only
    those. Each step is already incremental — unchanged files are skipped by
    graphify's own manifest, and labelling is skipped outright when every
    community already has a real name.

    Before any LLM step it prepares what the run needs: the custom provider entry
    in ~/.graphify/providers.json, the API-key env var, a running server, and a
    model loaded at a context length that fits both the card and the job. Chunk
    size, batch size and the reply budget are derived from the window each call
    actually gets, so nothing can overflow it. The `update` phase on its own
    needs no model and does not touch LM Studio.

.PARAMETER Phase
    Any of update, docs, label. All three, in that order, when omitted.

.PARAMETER Path
    Project root. Defaults to the current directory.

.PARAMETER Model
    LM Studio model key. Picked from the downloaded catalog when omitted: the
    workload is prose in and JSON out, so tool-use-trained models rank first and
    code-tuned ones last.

.PARAMETER Concurrency
    Parallel LLM calls, and the number of slots the model is loaded with.
    Defaults to 1. Raising it splits the context window rather than adding
    capacity, so each call gets proportionally less room.

.PARAMETER ContextLength
    Context length to load the model with. Derived from VRAM and the model's own
    maximum when omitted. A model already loaded with a smaller window, or with
    more parallel slots than this run needs, is unloaded and reloaded.

.PARAMETER Mode
    Passed to the docs phase as `graphify extract --mode`. It needs its own
    parameter rather than riding the passthrough: PowerShell prefix-matches a
    bare `--mode` to -Model and would bind the value as a model name.

.PARAMETER Force
    Full re-scan: skip the incremental manifest gate and the semantic cache.

.PARAMETER Relabel
    Rename every community instead of only the missing and placeholder ones.

.PARAMETER NoViz
    Skip graph.html regeneration in the label phase.

.PARAMETER DryRun
    Print the resolved graphify commands without running them, and without
    loading a model.

.EXAMPLE
    graphify-lmstudio.ps1

.EXAMPLE
    graphify-lmstudio.ps1 docs label

.EXAMPLE
    graphify-lmstudio.ps1 update -Path ..\other-project

.EXAMPLE
    graphify-lmstudio.ps1 docs -Force -Mode deep
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('update', 'docs', 'label')]
    [string[]] $Phase,
    [string] $Path = (Get-Location).Path,
    [string] $Model,
    [int]    $Concurrency = 1,
    [int]    $ContextLength = 0,
    [ValidateSet('deep')]
    [string] $Mode,
    [switch] $Force,
    [switch] $Relabel,
    [switch] $NoViz,
    [string] $Backend = 'lmstudio',
    [int]    $Port = 1234,
    [switch] $DryRun,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Rest
)

$ErrorActionPreference = 'Stop'

# A positional array parameter only claims the first value once a
# ValueFromRemainingArguments parameter exists, so `docs label` would bind docs
# and leak label into the graphify passthrough. Split them back apart by name.
$KnownPhases = @('update', 'docs', 'label')
if ($Rest) {
    $Phase = @($Phase) + @($Rest | Where-Object { $_ -in $KnownPhases })
    $Rest = @($Rest | Where-Object { $_ -notin $KnownPhases })
}
$Phase = @($Phase | Where-Object { $_ })
if (-not $Phase) { $Phase = $KnownPhases }
if ($Concurrency -lt 1) { $Concurrency = 1 }

# Extraction sends a doc chunk plus graphify's node/edge JSON schema prompt and
# gets back JSON whose size tracks the chunk's, so the window has to hold all
# three. The 6000 chunk ceiling is not a context limit: recall on a 7-8B model
# degrades on long inputs well before the window fills, and a chunk the model
# half-reads costs a re-extraction.
$DocsPromptOverhead = 2500
$DocsMaxReply = 8192
$MaxChunkTokens = 6000

# Labelling costs one community's worth of prompt per batch entry — its top_k
# node labels plus its god-node hints — against a much smaller reply.
$LabelReply = 2048
$LabelPromptOverhead = 512
$TokensPerCommunity = 280
$MaxBatchSize = 100

# Largest window either phase can still use: past this both the chunk budget and
# the batch size are pinned to their own ceilings and the extra KV cache buys
# nothing but VRAM pressure.
$MaxUsefulContext = [Math]::Max(
    $MaxChunkTokens + $DocsMaxReply + $DocsPromptOverhead,
    ($MaxBatchSize * $TokensPerCommunity) + $LabelReply + $LabelPromptOverhead)

# KV cache per token, measured across Q4 7-8B GGUFs: 57 KiB for qwen2.5-coder-7b,
# 106 KiB for qwen3-8b. Rounded well above both because the fit has to err small
# — `lms load` does not refuse a window too large for the card, it fills VRAM to
# the last hundred megabytes and reports success, leaving the run to stall in a
# partial offload. VramReserveMb covers the desktop's own allocation plus that
# error margin.
$KvKbPerToken = 128
$VramReserveMb = 2560

$ProvidersPath = Join-Path $HOME '.graphify/providers.json'
$ApiKeyVar = 'LMSTUDIO_API_KEY'
$BaseUrl = "http://localhost:$Port/v1"
$GraphPath = Join-Path $Path 'graphify-out/graph.json'

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string] $Message) Write-Host "    $Message" -ForegroundColor DarkGray }

function Get-LoadedModels {
    $raw = & lms ps --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try { return @($raw | ConvertFrom-Json) } catch { return @() }
}

function Get-LlmCatalog {
    $raw = & lms ls --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try { return @($raw | ConvertFrom-Json | Where-Object { $_.type -eq 'llm' }) } catch { return @() }
}

# graphify only ever sends prose to the model — source files go through its local
# AST extractors and never reach an LLM — so a code-tuned model is the wrong pick
# even on a code repo. Tool-use training is the closest signal the catalog
# carries for how reliably a model returns well-formed JSON.
function Select-BestModel {
    param([object[]] $Catalog)
    $ranked = foreach ($m in $Catalog) {
        if ([int] $m.maxContextLength -lt 8192) { continue }
        $score = 0
        if ($m.trainedForToolUse) { $score += 20 }
        if ("$($m.modelKey) $($m.displayName)" -match '(?i)coder|codellama|starcoder|codegemma|codestral') { $score -= 40 }
        [pscustomobject]@{ Entry = $m; Score = $score }
    }
    if (-not $ranked) { return $null }
    ($ranked | Sort-Object @{ Expression = { $_.Score }; Descending = $true },
                           @{ Expression = { [double] $_.Entry.sizeBytes }; Descending = $true } |
        Select-Object -First 1).Entry
}

function Get-VramTotalMb {
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return 0 }
    $raw = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return 0 }
    try { return [int] "$(@($raw)[0])".Trim() } catch { return 0 }
}

# Largest window that fits alongside the weights, bounded by the model's own
# maximum. Without an nvidia GPU to measure, that maximum is the only ceiling.
function Get-FittingContext {
    param([object] $Entry, [int] $Ceiling)
    $ctx = $Ceiling
    if ([int] $Entry.maxContextLength -gt 0) { $ctx = [Math]::Min($ctx, [int] $Entry.maxContextLength) }
    $vram = Get-VramTotalMb
    if ($vram -gt 0 -and [double] $Entry.sizeBytes -gt 0) {
        $kvMb = $vram - $VramReserveMb - [Math]::Ceiling([double] $Entry.sizeBytes / 1MB)
        $ctx = [Math]::Min($ctx, [Math]::Floor($kvMb * 1024 / $KvKbPerToken))
    }
    [Math]::Max(4096, [Math]::Floor($ctx / 1024) * 1024)
}

# Communities carrying no name or still holding graphify's 'Community N'
# placeholder. Read off the graph itself rather than the labels sidecar, so a
# re-clustering that invented new communities counts as stale.
function Get-CommunityState {
    param([string] $GraphFile)
    $names = @{}
    foreach ($n in (Get-Content $GraphFile -Raw | ConvertFrom-Json).nodes) {
        if ($null -eq $n.community) { continue }
        $names["$($n.community)"] = $n.community_name
    }
    $stale = @($names.Values | Where-Object { -not $_ -or $_ -match '^Community \d+$' }).Count
    [pscustomobject]@{ Total = $names.Count; Stale = $stale }
}

function Invoke-Graphify {
    param([string[]] $Arguments, [int] $ReplyCap)

    if ($DryRun) {
        Write-Host "graphify $($Arguments -join ' ')"
        return
    }
    # The provider's own reply cap is one value shared by every phase; this env
    # var overrides it, so each phase asks for what it actually needs.
    $env:GRAPHIFY_MAX_OUTPUT_TOKENS = "$ReplyCap"
    Write-Step "graphify $($Arguments -join ' ')"
    & graphify @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host "graphify $($Arguments[0]) failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path $Path)) { throw "No such path: $Path" }
if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
    throw "'graphify' not on PATH. Install with: uv tool install 'graphifyy[openai]'"
}
$needsModel = @($Phase | Where-Object { $_ -in 'docs', 'label' }).Count -gt 0
if ($needsModel -and -not (Get-Command lms -ErrorAction SilentlyContinue)) {
    throw "LM Studio CLI 'lms' not on PATH. Install LM Studio, then run: lms bootstrap"
}
if ($Phase -contains 'label' -and -not (Test-Path $GraphPath)) {
    throw "No graph found at $GraphPath. Run this without arguments to build one first."
}

Write-Step "Project: $Path  [$($Phase -join ', ')]"

# --- model ----------------------------------------------------------------
if ($needsModel) {
    $providers = @{}
    if (Test-Path $ProvidersPath) {
        $providers = Get-Content $ProvidersPath -Raw | ConvertFrom-Json -AsHashtable
    }
    $catalog = Get-LlmCatalog
    if (-not $Model) {
        $pick = Select-BestModel $catalog
        if (-not $pick) { throw "No LM Studio LLM with a usable context window found. Download one, or pass -Model <key>." }
        $Model = $pick.modelKey
    }
    $catalogEntry = $catalog | Where-Object { $_.modelKey -eq $Model } | Select-Object -First 1
    if (-not $catalogEntry) { throw "$Model is not in the LM Studio catalog. Check: lms ls" }

    $providerDirty = $false
    if (-not $providers.ContainsKey($Backend)) {
        Write-Step "Registering provider '$Backend' in $ProvidersPath"
        $providers[$Backend] = [ordered]@{
            base_url         = $BaseUrl
            default_model    = $Model
            env_key          = $ApiKeyVar
            model_env_key    = 'GRAPHIFY_LMSTUDIO_MODEL'
            temperature      = 0
            reasoning_effort = 'none'
            pricing          = @{ input = 0.0; output = 0.0 }
        }
        $providerDirty = $true
    }
    else {
        # A hybrid-reasoning model like Qwen3 spends most of its reply budget
        # thinking before it emits any JSON, and LM Studio ignores the
        # enable_thinking chat template kwarg. reasoning_effort it does honour,
        # and non-reasoning models ignore it, so it is safe to leave set.
        foreach ($kv in @{ default_model = $Model; reasoning_effort = 'none' }.GetEnumerator()) {
            if ($providers[$Backend][$kv.Key] -ne $kv.Value) {
                $providers[$Backend][$kv.Key] = $kv.Value
                $providerDirty = $true
            }
        }
        # max_completion_tokens wins over max_tokens in graphify's openai-compat
        # path, so a stale one silently caps every reply for anyone calling
        # graphify directly. Each phase sets its own cap through
        # GRAPHIFY_MAX_OUTPUT_TOKENS, which overrides whatever the entry holds.
        if ($providers[$Backend].ContainsKey('max_completion_tokens')) {
            $providers[$Backend].Remove('max_completion_tokens')
            $providerDirty = $true
        }
        if ($providerDirty) { Write-Note "Updating provider '$Backend' for $Model" }
    }
    if ($providerDirty -and -not $DryRun) {
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

    $vramCtx = Get-FittingContext -Entry $catalogEntry -Ceiling ([int]::MaxValue)
    $targetCtx = if ($ContextLength -gt 0) {
        [Math]::Min($ContextLength, [int] $catalogEntry.maxContextLength)
    } else {
        Get-FittingContext -Entry $catalogEntry -Ceiling ($MaxUsefulContext * $Concurrency)
    }
    if ($ContextLength -gt $targetCtx) {
        Write-Note "$Model tops out at $targetCtx context; loading at that instead of $ContextLength"
    }
    if ($targetCtx -gt $vramCtx) {
        Write-Note "$targetCtx context is past the ${vramCtx} this card is estimated to hold; expect a partial offload"
    }

    # Parallel slots divide one shared window rather than each getting their own
    # — VRAM at -c 16384 is identical for --parallel 1 and --parallel 4 — so a
    # model loaded with more slots than this run uses hands every call a smaller
    # prompt window than its context length advertises.
    $loaded = Get-LoadedModels | Where-Object { $_.identifier -eq $Model } | Select-Object -First 1
    $reusable = $loaded -and [int] $loaded.contextLength -ge $targetCtx -and [int] $loaded.parallel -le $Concurrency

    if (-not $DryRun -and -not $reusable) {
        # The fit was computed against the whole card, so anything else resident
        # would push this load into a partial offload and a tenfold slowdown.
        foreach ($other in Get-LoadedModels | Where-Object { $_.type -eq 'llm' }) {
            Write-Note "Unloading $($other.identifier)"
            & lms unload $other.identifier | Where-Object { $_ } | Write-Note
        }
        Write-Step "Loading $Model at $targetCtx context, $Concurrency slot(s)"
        & lms load $Model -y --gpu max -c "$targetCtx" --parallel "$Concurrency" | Where-Object { $_ } | Write-Note
        $loaded = Get-LoadedModels | Where-Object { $_.identifier -eq $Model } | Select-Object -First 1
        if (-not $loaded) {
            throw "Failed to load $Model at $targetCtx context. If it did not fit VRAM, retry with a smaller -ContextLength."
        }
    }

    # Under -DryRun a model that would have been reloaded is still resident, and
    # its current window is not the one the run would get — report the target.
    $effective = if ($reusable -or (-not $DryRun -and $loaded)) { $loaded } else { $null }
    $ctx = if ($effective) { [int] $effective.contextLength } else { $targetCtx }
    $slots = if ($effective) { [Math]::Max(1, [int] $effective.parallel) } else { $Concurrency }
    $window = [Math]::Floor($ctx / $slots)
    Write-Note "$Model - ${ctx}-token context across $slots slot(s), ${window} per call"
}

$started = Get-Date

# --- update ---------------------------------------------------------------
if ($Phase -contains 'update') {
    $cmd = @('update', $Path)
    if ($Force) { $cmd += '--force' }
    if ($Rest) { $cmd += $Rest }
    Invoke-Graphify -Arguments $cmd -ReplyCap $DocsMaxReply
}

# --- docs -----------------------------------------------------------------
if ($Phase -contains 'docs') {
    $reply = [Math]::Min($DocsMaxReply, [Math]::Floor($window / 2))
    $budget = [Math]::Min($MaxChunkTokens,
              [Math]::Max(1000, $window - $reply - $DocsPromptOverhead))
    Write-Note "token-budget $budget, reply cap $reply"

    $cmd = @('extract', $Path, '--backend', $Backend, '--model', $Model,
              '--token-budget', "$budget", '--max-concurrency', "$Concurrency")
    if ($Mode) { $cmd += @('--mode', $Mode) }
    if ($Force) { $cmd += '--force' }
    if ($Rest) { $cmd += $Rest }
    Invoke-Graphify -Arguments $cmd -ReplyCap $reply
}

# --- label ----------------------------------------------------------------
if ($Phase -contains 'label') {
    $state = if ($DryRun -and -not (Test-Path $GraphPath)) { $null } else { Get-CommunityState $GraphPath }
    if ($state -and $state.Stale -eq 0 -and -not $Relabel) {
        Write-Note "all $($state.Total) communities already named; skipping (-Relabel to redo them)"
    }
    else {
        if ($state) { Write-Note "$($state.Stale) of $($state.Total) communities need a name" }
        $batch = [Math]::Min($MaxBatchSize, [Math]::Max(4,
                 [Math]::Floor(($window - $LabelReply - $LabelPromptOverhead) / $TokensPerCommunity)))
        Write-Note "batch-size $batch, reply cap $LabelReply"

        $cmd = @('label', $Path, '--backend', $Backend, '--model', $Model,
                  '--batch-size', "$batch", '--max-concurrency', "$Concurrency")
        if (-not $Relabel) { $cmd += '--missing-only' }
        if ($NoViz) { $cmd += '--no-viz' }
        if ($Rest) { $cmd += $Rest }
        Invoke-Graphify -Arguments $cmd -ReplyCap $LabelReply
    }
}

if ($DryRun) { return }

# --- verify ---------------------------------------------------------------
Write-Step "Done in $([Math]::Round(((Get-Date) - $started).TotalMinutes, 1)) min"
if (Test-Path $GraphPath) {
    $state = Get-CommunityState $GraphPath
    Write-Note "$($state.Total) communities, $($state.Stale) unnamed"
    if ($state.Stale -gt 0 -and $Phase -contains 'label') {
        Write-Host "    $($state.Stale) communities kept 'Community N' - the model overflowed context or returned unparseable JSON. Retry with: $($MyInvocation.MyCommand.Name) label -Concurrency $Concurrency" -ForegroundColor Yellow
    }
}
