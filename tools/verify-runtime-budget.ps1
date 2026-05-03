# verify-runtime-budget.ps1 — Validate runtime-budget.json contract and profile strength
#   pwsh ./tools/verify-runtime-budget.ps1 [-Json]

[CmdletBinding()]
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

try {
    $path = Join-Path $RepoRoot 'runtime-budget.json'
    $schemaPath = Join-Path $RepoRoot 'schemas/runtime-budget.schema.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'missing runtime-budget.json' }
    if (-not (Test-Path -LiteralPath $schemaPath)) { throw 'missing schemas/runtime-budget.schema.json' }
    $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    $ord = @($j.ordering | ForEach-Object { [string]$_ })
    if (($ord -join ',') -ne 'quick,standard,strict') {
        [void]$failures.Add('ordering must be exactly: quick, standard, strict')
    }

    $q = $j.profiles.quick
    $s = $j.profiles.standard
    $t = $j.profiles.strict
    if ([int]$q.targetSeconds -ge [int]$s.targetSeconds -or [int]$s.targetSeconds -ge [int]$t.targetSeconds) {
        [void]$failures.Add('targetSeconds must increase: quick < standard < strict')
    }
    if (-not [bool]$t.requireGit -or -not [bool]$t.requireBash -or -not [bool]$t.requireCleanWorkingTree) {
        [void]$failures.Add('strict profile must require Git, Bash, and clean working tree')
    }
    if ([bool]$q.requireGit -or [bool]$q.requireBash -or [bool]$q.requireCleanWorkingTree) {
        [void]$warnings.Add('quick profile should leave git/bash/clean-tree optional for local-first Windows')
    }

    $mq = [int]$q.maxFilesScanned
    $ms = [int]$s.maxFilesScanned
    $mt = [int]$t.maxFilesScanned
    if ($mq -ge $ms -or $ms -ge $mt) {
        [void]$failures.Add('maxFilesScanned must increase: quick < standard < strict')
    }

    $ap = @($j.approvalRequiredFor | ForEach-Object { [string]$_ })
    foreach ($lbl in @('Critical', 'Production', 'Incident', 'Migration', 'Release', 'Destructive')) {
        if ($ap -notcontains $lbl) {
            [void]$failures.Add("approvalRequiredFor must include '$lbl'")
        }
    }

    foreach ($req in @('skipped', 'warn', 'unknown', 'not_run', 'degraded', 'blocked')) {
        $ntp = @($j.neverTreatAsPassed | ForEach-Object { [string]$_ })
        if ($ntp -notcontains $req) {
            [void]$failures.Add("neverTreatAsPassed must include '$req'")
        }
    }

    [void]$checks.Add([ordered]@{
            name   = 'runtime-budget-parse'
            status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' })
            detail = 'runtime-budget.json + schema presence'
        })
    [void]$findings.Add([ordered]@{ file = 'runtime-budget.json'; profiles = 'quick,standard,strict' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-runtime-budget' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-runtime-budget: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
