# verify-quality-gates.ps1 — Structural checks for quality-gates/*.json (manifest-governed gates)
#   pwsh ./tools/verify-quality-gates.ps1 [-Json]

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

function Fail {
    param([string]$Message)
    [void]$script:failures.Add($Message)
}

function Test-SafeArg {
    param([string]$Arg, [string]$Ctx)
    if ([string]::IsNullOrWhiteSpace($Arg)) { return }
    if ($Arg -match '[`;&|]') { Fail "${Ctx}: unsafe metacharacter in argument" }
    if ($Arg -match '\.\.') { Fail "${Ctx}: path traversal in argument" }
}

function Test-GateFile {
    param([string]$RelPath)

    $full = Join-Path $RepoRoot $RelPath
    if (-not (Test-Path -LiteralPath $full)) {
        Fail "missing $RelPath"
        return
    }

    $gate = $null
    try { $gate = Get-Content -LiteralPath $full -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { Fail "$RelPath invalid JSON"; return }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($RelPath)
    $id = [string]$gate.id
    $domain = [string]$gate.domain

    if ($domain -ne $base) {
        Fail "$RelPath domain '$domain' must match filename base '$base'"
    }

    if ($id -notmatch '^gate\.[a-z0-9-]+$') { Fail "$RelPath invalid id $id" }

    $req = @('schemaVersion', 'title', 'requiredValidators', 'allowedWarnings', 'blockingWarnings', 'requiredEvidence', 'approvalRequirements', 'strictModeBehavior')
    foreach ($k in $req) {
        if (-not ($gate.PSObject.Properties.Name -contains $k)) { Fail "$RelPath missing property $k" }
    }

    if (-not $gate.blockingWarnings -or @($gate.blockingWarnings).Count -lt 1) {
        Fail "$RelPath blockingWarnings must have at least one entry"
    }

    foreach ($v in @($gate.requiredValidators)) {
        $sid = [string]$v.id
        $scriptRel = [string]$v.script
        if ([string]::IsNullOrWhiteSpace($scriptRel)) { Fail "$RelPath validator $sid missing script"; continue }
        if ($scriptRel -notmatch '^tools/[A-Za-z0-9._-]+\.ps1$') { Fail "$RelPath validator $sid bad script path" }
        foreach ($a in @($v.arguments | ForEach-Object { [string]$_ })) { Test-SafeArg -Arg $a -Ctx "${RelPath}.${sid}" }
        $vf = Join-Path $RepoRoot ($scriptRel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $vf)) { Fail "$RelPath validator $sid missing file $scriptRel" }
    }

    if ($id -eq 'gate.release') {
        if (-not ($gate.PSObject.Properties.Name -contains 'passInterpretation')) {
            Fail 'gate.release must declare passInterpretation'
        }
        else {
            $pi = $gate.passInterpretation
            if (-not $pi.onlyStatusOkIsPass) { Fail 'gate.release passInterpretation.onlyStatusOkIsPass must be true' }
            $mustStatuses = @('skip', 'warn', 'unknown', 'degraded', 'blocked', 'fail')
            $have = @($pi.statusesNeverEquivalentToPassed | ForEach-Object { [string]$_ })
            foreach ($ms in $mustStatuses) {
                if ($have -notcontains $ms) {
                    Fail "gate.release passInterpretation.statusesNeverEquivalentToPassed must include '$ms'"
                }
            }
            $mustAlias = @('skipped', 'not_run')
            $aliases = @($pi.nonPassStatusAliases | ForEach-Object { [string]$_ })
            foreach ($ma in $mustAlias) {
                if ($aliases -notcontains $ma) {
                    Fail "gate.release passInterpretation.nonPassStatusAliases must include '$ma' (runtime-budget alignment)"
                }
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = $id; status = 'ok'; detail = $RelPath })
}

try {
    $dir = Join-Path $RepoRoot 'quality-gates'
    if (-not (Test-Path -LiteralPath $dir)) {
        Fail 'quality-gates directory missing'
    }
    else {
        $expected = @('docs', 'skills', 'release', 'bootstrap', 'adapters', 'security')
        foreach ($name in $expected) {
            Test-GateFile -RelPath "quality-gates/$name.json"
        }
        $extra = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | ForEach-Object { $_.Name }
        foreach ($e in $extra) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($e)
            if ($expected -notcontains $stem) {
                Fail "unexpected quality-gates file: $e (manifest is closed-set)"
            }
        }
    }

    $schemaPath = Join-Path $RepoRoot 'schemas/quality-gate.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath)) { Fail 'schemas/quality-gate.schema.json missing' }
    else {
        $sch = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        if (-not ($sch.PSObject.Properties.Name -contains '$schema')) {
            Fail 'schemas/quality-gate.schema.json missing $schema'
        }
    }

    [void]$checks.Add([ordered]@{ name = 'quality-gate-schema'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'schemas/quality-gate.schema.json present' })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-quality-gates' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-quality-gates: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
