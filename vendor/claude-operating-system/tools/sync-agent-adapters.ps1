# sync-agent-adapters.ps1 — Read-only parity check: manifest ↔ templates/adapters (no domain assets)
#   pwsh ./tools/sync-agent-adapters.ps1 [-Json] [-WhatIf]
# Canonical adapter templates live under templates/adapters; projects receive copies via init-project / os-update.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()
$actions = [System.Collections.Generic.List[string]]::new()

try {
    [void]$actions.Add('invoke verify-agent-adapters.ps1 (read-only template/manifest parity)')
    if (-not $PSCmdlet.ShouldProcess($RepoRoot, 'verify adapter templates vs manifest')) {
        [void]$warnings.Add('WhatIf / -Confirm:$false: skipped verify-agent-adapters (dry-run)')
        [void]$checks.Add([ordered]@{ name = 'adapter-sync'; status = 'skip'; detail = 'WhatIf dry-run' })
    }
    else {
        $ap = @{}
        if ($Json) { $ap['Json'] = $true }
        & (Join-Path $RepoRoot 'tools/verify-agent-adapters.ps1') @ap
        if ($LASTEXITCODE -ne 0) {
            [void]$failures.Add('verify-agent-adapters.ps1 failed')
        }
        [void]$checks.Add([ordered]@{ name = 'adapter-sync'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'manifest parity' })
    }
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'sync-agent-adapters' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings) -Actions @($actions)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "sync-agent-adapters: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
