# verify-gate-results.ps1 — Align no-false-green contract: gate-status-contract, runtime-budget, release gate, validator envelope
#   pwsh ./tools/verify-gate-results.ps1 [-Json]

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

function Fail { param([string]$Message) [void]$script:failures.Add($Message) }

function Get-SortedUnique {
    param([string[]]$Items)
    return @($Items | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
}

try {
    $contractPath = Join-Path $RepoRoot 'gate-status-contract.json'
    $schemaPath = Join-Path $RepoRoot 'schemas/gate-result.schema.json'
    if (-not (Test-Path -LiteralPath $contractPath)) { throw 'missing gate-status-contract.json' }
    if (-not (Test-Path -LiteralPath $schemaPath)) { throw 'missing schemas/gate-result.schema.json' }
    $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $c = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

    if (-not [bool]$c.onlyOkUnlocks) { Fail 'gate-status-contract.onlyOkUnlocks must be true' }
    $pass = @($c.passStatuses | ForEach-Object { [string]$_ })
    if (($pass | Sort-Object -Unique) -ne @('ok')) { Fail 'gate-status-contract.passStatuses must be exactly [ok]' }

    $expectedCanon = @('blocked', 'degraded', 'fail', 'not_run', 'ok', 'skip', 'unknown', 'warn')
    $haveCanon = Get-SortedUnique -Items @($c.canonicalStatuses | ForEach-Object { [string]$_ })
    if (($haveCanon -join ',') -ne ($expectedCanon -join ',')) {
        Fail "gate-status-contract.canonicalStatuses must match canonical set (sorted): $($expectedCanon -join ',')"
    }

    foreach ($req in @($c.runtimeBudgetNeverTreatAsPassedMustInclude | ForEach-Object { [string]$_ })) {
        $rbPath = Join-Path $RepoRoot 'runtime-budget.json'
        $rb = Get-Content -LiteralPath $rbPath -Raw | ConvertFrom-Json
        $ntp = @($rb.neverTreatAsPassed | ForEach-Object { [string]$_ })
        if ($ntp -notcontains $req) {
            Fail "runtime-budget.neverTreatAsPassed must include '$req' (gate-status-contract.runtimeBudgetNeverTreatAsPassedMustInclude)"
        }
    }

    $relPath = 'quality-gates/release.json'
    $relFull = Join-Path $RepoRoot $relPath
    $gate = Get-Content -LiteralPath $relFull -Raw | ConvertFrom-Json
    if (-not $gate.passInterpretation.onlyStatusOkIsPass) {
        Fail 'quality-gates/release.json passInterpretation.onlyStatusOkIsPass must be true'
    }
    $must = @('skip', 'warn', 'unknown', 'degraded', 'blocked', 'fail', 'not_run')
    $haveNever = @($gate.passInterpretation.statusesNeverEquivalentToPassed | ForEach-Object { [string]$_ })
    foreach ($m in $must) {
        if ($haveNever -notcontains $m) {
            Fail "quality-gates/release.json passInterpretation.statusesNeverEquivalentToPassed must include '$m'"
        }
    }
    $aliases = @($gate.passInterpretation.nonPassStatusAliases | ForEach-Object { [string]$_ })
    foreach ($a in @('skipped', 'not_run')) {
        if ($aliases -notcontains $a) {
            Fail "quality-gates/release.json passInterpretation.nonPassStatusAliases must include '$a'"
        }
    }

    $envSchemaPath = Join-Path $RepoRoot 'schemas/os-validator-envelope.schema.json'
    $es = Get-Content -LiteralPath $envSchemaPath -Raw | ConvertFrom-Json
    $enum = @($es.properties.status.enum | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($enum -join ',') -ne ($expectedCanon -join ',')) {
        Fail "schemas/os-validator-envelope.properties.status.enum must match canonicalStatuses (sorted): expected $($expectedCanon -join ',') got $($enum -join ',')"
    }

    [void]$checks.Add([ordered]@{
            name   = 'gate-status-contract-alignment'
            status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' })
            detail = 'gate-status-contract.json + runtime-budget + release + envelope'
        })
    [void]$findings.Add([ordered]@{ canonicalStatusCount = $expectedCanon.Count })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-gate-results' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-gate-results: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
