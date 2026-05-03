# append-approval-log.ps1 — Append one JSON line to logs/approval-log.jsonl (human approval ledger)
#   pwsh ./tools/append-approval-log.ps1 -Operation ... -RiskLevel critical -Approver ... -Scope ... `
#       -CommandOrActionApproved '...' (-ExpiresAt '2026-05-04T12:00:00Z' | -OneTimeUse) `
#       -RelatedValidationEvidence @('...') -RollbackPlanReference '...' [-Json] [-WhatIf]
# Requires: either -ExpiresAt (RFC 3339 UTC) or -OneTimeUse (or both).

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Operation,
    [Parameter(Mandatory = $true)]
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel,

    [Parameter(Mandatory = $true)][string]$Approver,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$CommandOrActionApproved,

    [string]$ExpiresAt = '',

    [switch]$OneTimeUse,

    [Parameter(Mandatory = $true)]
    [string[]]$RelatedValidationEvidence,

    [Parameter(Mandatory = $true)][string]$RollbackPlanReference,

    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

try {
    if ([string]::IsNullOrWhiteSpace($ExpiresAt) -and -not $OneTimeUse) {
        throw 'Provide -ExpiresAt (RFC 3339 UTC) and/or -OneTimeUse.'
    }
    $ev = @($RelatedValidationEvidence | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    if ($ev.Count -lt 1) { throw 'RelatedValidationEvidence must contain at least one non-empty string.' }

    $expObj = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($ExpiresAt)) {
        $expObj['expiresAt'] = $ExpiresAt.Trim()
    }
    if ($OneTimeUse) {
        $expObj['oneTimeUse'] = $true
    }

    $row = [ordered]@{
        timestamp                 = (Get-Date).ToUniversalTime().ToString('o')
        operation                 = $Operation.Trim()
        riskLevel                 = $RiskLevel
        approver                  = $Approver.Trim()
        scope                     = $Scope.Trim()
        commandOrActionApproved   = $CommandOrActionApproved.Trim()
        expirationOrUse           = [ordered]@{}
        relatedValidationEvidence = @($ev)
        rollbackPlanReference     = $RollbackPlanReference.Trim()
    }
    foreach ($k in $expObj.Keys) {
        $row.expirationOrUse[$k] = $expObj[$k]
    }

    $logsDir = Join-Path $RepoRoot 'logs'
    $logPath = Join-Path $logsDir 'approval-log.jsonl'
    $line = ($row | ConvertTo-Json -Compress -Depth 8)
    if (-not $PSCmdlet.ShouldProcess($logPath, 'Append one approval ledger line')) {
        [void]$checks.Add([ordered]@{ name = 'append-approval-log'; status = 'ok'; detail = 'skipped (-WhatIf)' })
    }
    else {
        if (-not (Test-Path -LiteralPath $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
        [void]$checks.Add([ordered]@{ name = 'append-approval-log'; status = 'ok'; detail = 'appended one line' })
    }
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'append-approval-log' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @(@([ordered]@{ path = 'logs/approval-log.jsonl' }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "append-approval-log: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
