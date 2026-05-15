# verify-exit-codes.ps1 — Static exit-code hygiene analyzer for tools/*.ps1
# Detects PowerShell scripts that have failure paths (exit 1 / throw) but no explicit
# exit 0 on the success path. $null -ne 0 is True in PowerShell, so a script that
# falls off the end without exit 0 may leave $LASTEXITCODE stale from a prior command.
#   pwsh ./tools/verify-exit-codes.ps1
#   pwsh ./tools/verify-exit-codes.ps1 -Json
#   pwsh ./tools/verify-exit-codes.ps1 -Strict  # warn becomes fail

param(
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures  = [System.Collections.Generic.List[string]]::new()
$warnings  = [System.Collections.Generic.List[string]]::new()
$checks    = [System.Collections.Generic.List[object]]::new()
$findings  = [System.Collections.Generic.List[object]]::new()
$suspects  = [System.Collections.Generic.List[object]]::new()

# Scripts that are intentionally exit-less on success (pure dispatcher / dot-source stubs).
$allowList = @('lib/safe-output.ps1', 'lib/validation-envelope.ps1')

function Test-HasExplicitExit0 {
    param([string]$Source)
    # Accept: bare 'exit 0', or the Json-path pattern ConvertTo-Json|Write-Output then exit 0
    return $Source -match '(?m)^\s*exit\s+0\s*$'
}

function Test-HasFailurePath {
    param([string]$Source)
    # Failure path indicators: explicit exit 1, throw, exit [int]$code, exit $LASTEXITCODE
    return ($Source -match 'exit\s+1') -or
           ($Source -match 'throw\s+') -or
           ($Source -match 'exit\s+\[int\]') -or
           ($Source -match "exit\s+\`$LASTEXITCODE")
}

$toolScripts = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tools') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in $toolScripts) {
    $rel = 'tools/' + $file.Name
    if ($allowList | Where-Object { $rel -like "*$_" }) { continue }

    try {
        $src = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    } catch {
        [void]$warnings.Add("Could not read ${rel}: $($_.Exception.Message)")
        continue
    }

    $hasFailure = Test-HasFailurePath -Source $src
    $hasExit0   = Test-HasExplicitExit0 -Source $src

    if ($hasFailure -and -not $hasExit0) {
        [void]$suspects.Add([ordered]@{
            script   = $rel
            hasExit1 = ($src -match 'exit\s+1')
            hasThrow = ($src -match 'throw\s+')
            verdict  = 'missing explicit exit 0 on success path'
        })
    }

    [void]$checks.Add([ordered]@{
        name   = $rel
        status = if ($hasFailure -and -not $hasExit0) { 'warn' } else { 'ok' }
        detail = if ($hasFailure -and -not $hasExit0) { 'missing exit 0' } else { 'ok' }
    })
}

$sw.Stop()

foreach ($s in $suspects) {
    $msg = "PowerShell exit code hygiene: $($s.script) has failure path but no explicit exit 0"
    if ($Strict) {
        [void]$failures.Add($msg)
    } else {
        [void]$warnings.Add($msg)
    }
    [void]$findings.Add([ordered]@{ type = 'exit-code-suspect'; script = $s.script; verdict = $s.verdict })
}

$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-exit-codes' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'verify-exit-codes'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
    if ($suspects.Count -eq 0) {
        Write-Host "OK:  tools/*.ps1 ($($toolScripts.Count) scripts checked, 0 suspects)"
    } else {
        foreach ($s in $suspects) {
            $tag = if ($Strict) { 'FAIL' } else { 'WARN' }
            Write-Host "${tag}: $($s.script) — $($s.verdict)"
        }
    }
    Write-Host ''
    Write-Host "Exit code hygiene: $($toolScripts.Count) checked, $($suspects.Count) suspect(s), strict=$([bool]$Strict)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
