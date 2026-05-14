# invoke-safe-apply.ps1 — Invoke a manifest tool with dry-run / WhatIf forwarding and a JSON write summary
#   pwsh ./tools/invoke-safe-apply.ps1 -ToolId sync-skills -DryRun [-Json]
#   pwsh ./tools/invoke-safe-apply.ps1 -ToolId os-update-project -DryRun -PassArgs @('-ProjectPath','../x')
# Requires script-manifest.json entry; respects safeApply.generatedWriteTargets for the summary envelope.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ToolId,

    [switch]$DryRun,

    [switch]$WhatIf,

    [switch]$Confirm,

    [switch]$Json,

    [string[]]$PassArgs = @()
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/safe-apply.ps1')

$mfPath = Join-Path $RepoRoot 'script-manifest.json'
if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing script-manifest.json' }
$mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json
$tool = @($mf.tools | Where-Object { $_.id -eq $ToolId } | Select-Object -First 1)[0]
if (-not $tool) { throw "unknown ToolId: $ToolId" }

$rel = [string]$tool.path
if ($rel -notmatch '(?i)^tools/.+\.ps1$') { throw "invoke-safe-apply only supports tools/*.ps1 (got $rel)" }
$full = Join-Path $RepoRoot $rel
if (-not (Test-Path -LiteralPath $full)) { throw "missing script: $rel" }

$raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
$sig = Get-SafeApplySignalsFromScriptText -Raw $raw
$wantSim = [bool]($DryRun -or $WhatIf)
$forward = @(Get-SafeApplyForwardArgs -Signals $sig -WantDryRun $wantSim)
if ($wantSim -and $forward.Count -eq 0) {
    throw "Tool $ToolId does not support -DryRun or -WhatIf / SupportsShouldProcess; see docs/SAFE-APPLY.md"
}

$invoke = [System.Collections.Generic.List[string]]::new()
[void]$invoke.Add('-NoProfile')
[void]$invoke.Add('-File')
[void]$invoke.Add($full)
foreach ($x in $forward) { [void]$invoke.Add($x) }
if ($Confirm) { [void]$invoke.Add('-Confirm') }
if ($Json) { [void]$invoke.Add('-Json') }
foreach ($x in $PassArgs) { [void]$invoke.Add($x) }

$declaredWrites = @(@($tool.writes | ForEach-Object { [string]$_ }) | Where-Object { $_ -match '\S' })
$gen = @()
$rollback = ''
if ($tool.PSObject.Properties.Name -contains 'safeApply' -and $tool.safeApply) {
    $sa = $tool.safeApply
    if ($sa.PSObject.Properties.Name -contains 'generatedWriteTargets') {
        $gen = @($sa.generatedWriteTargets | ForEach-Object { [string]$_ })
    }
    if ($sa.PSObject.Properties.Name -contains 'rollbackNote') {
        $rollback = [string]$sa.rollbackNote
    }
}

$null = & pwsh @invoke
$code = $LASTEXITCODE

$summary = [ordered]@{
    tool                    = 'invoke-safe-apply'
    targetToolId            = $ToolId
    targetScript            = $rel
    dryRunOrWhatIfRequested = $wantSim
    forwarded               = @($forward + $(if ($Confirm) { '-Confirm' } else { @() }) + $(if ($Json) { '-Json' } else { @() }) + @($PassArgs))
    manifestDeclaredWrites  = @($declaredWrites)
    generatedWriteTargets   = @($gen)
    rollbackNote            = $rollback
    childExitCode           = [int]$code
    writeRisk               = [string]$tool.writeRisk
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 8 -Compress | Write-Output
}
else {
    Write-Host "invoke-safe-apply: $($summary.targetToolId) exit $($summary.childExitCode) (dryRun=$($summary.dryRunOrWhatIfRequested))"
}

exit $code
