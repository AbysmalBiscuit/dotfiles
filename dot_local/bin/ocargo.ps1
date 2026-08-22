<#
.SYNOPSIS
    Run cargo with compiler optimizations enabled.

.DESCRIPTION
    PowerShell port of the fish `ocargo` function. Dot-source this file from your
    profile to get the `ocargo` function, or invoke the script directly.

.EXAMPLE
    ocargo -l build --release
#>

function ocargo {
    $short = @{ n = 'nightly'; f = 'fat'; l = 'lto'; d = 'dylib'; m = 'mold'; h = 'help' }
    $long = @{
        'nightly' = 'nightly'; 'fat' = 'fat'; 'lto' = 'lto'; 'dylib' = 'dylib'
        'mold' = 'mold'; 'no-mold' = 'noMold'; 'debug' = 'debug'; 'help' = 'help'
    }

    # Seed every flag: under Set-StrictMode, reading an absent hashtable key throws.
    $flag = @{}
    foreach ($name in @($short.Values) + @($long.Values)) { $flag[$name] = $false }
    $index = 0
    while ($index -lt $args.Count) {
        $token = [string]$args[$index]
        if ($token -cmatch '^--([a-z-]+)$' -and $long.ContainsKey($Matches[1])) {
            $flag[$long[$Matches[1]]] = $true
        }
        elseif ($token -cmatch '^-([a-z]+)$' -and
                @($Matches[1].ToCharArray() | Where-Object { -not $short.ContainsKey([string]$_) }).Count -eq 0) {
            foreach ($char in $Matches[1].ToCharArray()) { $flag[$short[[string]$char]] = $true }
        }
        else { break }
        $index++
    }
    $cargoArgs = @(if ($index -lt $args.Count) { $args[$index..($args.Count - 1)] })

    if ($flag.fat -and $flag.lto) {
        Write-Error '-f/--fat and -l/--lto are mutually exclusive'
        return
    }
    if ($flag.mold -and $flag.noMold) {
        Write-Error '-m/--mold and --no-mold are mutually exclusive'
        return
    }

    if ($flag.help) {
        Write-Host @'
Run cargo with compiler optimizations enabled

Usage: ocargo [OCARGO_OPTS] CARGO_CMD [CARGO_CMD_OPTS]

OCARGO_OPTS:
-n, --nightly    Use nightly compiler
-f, --fat        Enable fat LTO
-l, --lto        Enable thin LTO
-d, --dylib      Enable dylib-lto flag
-m, --mold       Use mold linker, even if $MOLD isn't set
--no-mold        Don't use mold linker, even if it's available
-h, --help       Print help
--debug          Print ocargo debug information

Run 'cargo --help' to see help for cargo

PowerShell swallows a bare '--', so quote it when forwarding args to the
binary under test: ocargo run '--' --my-arg
'@
        return
    }

    $rustFlags = if ($env:RUSTFLAGS_RELEASE) { $env:RUSTFLAGS_RELEASE }
    elseif ($env:RUSTFLAGS) { $env:RUSTFLAGS }
    else { '' }

    if ($rustFlags) {
        $defaults = @(
            @{ Marker = 'target-cpu'; Flag = '-C target-cpu=native' }
            @{ Marker = 'opt-level=3'; Flag = '-C opt-level=3' }
            @{ Marker = 'debuginfo'; Flag = '-C debuginfo=none' }
            @{ Marker = 'debug_assertions'; Flag = '-C debug_assertions=no' }
            @{ Marker = 'codegen-units'; Flag = '-C codegen-units=1' }
        )
        foreach ($default in $defaults) {
            if ($rustFlags -notlike "*$($default.Marker)*") { $rustFlags += " $($default.Flag)" }
        }
    }
    else {
        $rustFlags = '-C target-cpu=native -C opt-level=3 -C debuginfo=none -C debug_assertions=no -C codegen-units=1'
    }

    if (($flag.mold -or $env:MOLD) -and -not $flag.noMold) {
        $moldCommand = Get-Command mold -ErrorAction SilentlyContinue
        $moldPath = if ($env:MOLD) { $env:MOLD } elseif ($moldCommand) { $moldCommand.Source }
        if ($moldPath) { $rustFlags += " -C link-arg=-fuse-ld=$moldPath" }
        elseif ($flag.mold) { Write-Warning 'ocargo: mold not found on PATH, linking with the default linker' }
    }

    if ($flag.lto) { $rustFlags += ' -C lto=thin -C embed-bitcode=yes' }
    if ($flag.fat) { $rustFlags += ' -C lto=fat -C embed-bitcode=yes' }

    if ($flag.nightly) {
        $hasNightly = if ($null -ne $env:HAS_NIGHTLY_RUST) {
            $env:HAS_NIGHTLY_RUST -eq 'true'
        }
        else {
            [bool](@(& rustup toolchain list 2>$null) -match '^nightly')
        }
        if (-not $hasNightly) {
            Write-Host 'nightly rust is not available. to install it run:'
            Write-Host 'rustup toolchain install nightly'
            return
        }
        $cargoArgs = @('+nightly') + $cargoArgs
        if ($flag.dylib) { $rustFlags += ' -Zdylib-lto' }
    }

    if ($flag.debug) {
        Write-Host 'ocargo debug information:'
        Write-Host "RUSTFLAGS='$rustFlags'"
        Write-Host "cargo $cargoArgs"
        return
    }

    $previousRustFlags = $env:RUSTFLAGS
    $env:RUSTFLAGS = $rustFlags
    try { & cargo @cargoArgs }
    finally { $env:RUSTFLAGS = $previousRustFlags }
}

if ($MyInvocation.InvocationName -ne '.') { ocargo @args }
