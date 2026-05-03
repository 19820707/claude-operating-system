# sync-generated-targets.ps1 — Regenerate derived skill copies; run adapter template parity (manifest-driven)
#   pwsh ./tools/sync-generated-targets.ps1 [-Json] [-WhatIf]

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Json,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()

try {
    $skArgs = @()
    if ($Json) { $skArgs += '-Json' }
    if ($WhatIf -or -not $PSCmdlet.ShouldProcess($RepoRoot, 'sync skills to generated targets')) {
        $skArgs += '-DryRun'
    }
    & (Join-Path $RepoRoot 'tools/sync-skills.ps1') @skArgs
    if ($LASTEXITCODE -ne 0) { [void]$failures.Add('sync-skills.ps1 failed') }

    if ($WhatIf -or -not $PSCmdlet.ShouldProcess($RepoRoot, 'adapter template parity vs manifest')) {
        [void]$warnings.Add('sync-agent-adapters skipped (WhatIf / declined)')
    }
    else {
        $aaArgs = @()
        if ($Json) { $aaArgs += '-Json' }
        & (Join-Path $RepoRoot 'tools/sync-agent-adapters.ps1') @aaArgs
        if ($LASTEXITCODE -ne 0) { [void]$failures.Add('sync-agent-adapters.ps1 failed') }
    }

    [void]$findings.Add([ordered]@{ skillsCanonical = 'source/skills/'; adaptersCanonical = 'templates/adapters/' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'sync-generated-targets' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @([ordered]@{ name = 'sync-generated'; status = $st; detail = 'sync-skills (+ sync-agent-adapters when confirmed)' }) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "sync-generated-targets: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
