# verify-generated-drift.ps1 — Canonical vs generated targets + generation header contract (skills + adapter manifest)
#   pwsh ./tools/verify-generated-drift.ps1 [-Json] [-Strict]   # -Strict: drift/marker issues fail (never ok)

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Strict
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

function Get-LastJsonObjectFromLines {
    param([string[]]$Lines)
    $c = @($Lines | Where-Object { $_ -match '^\s*\{' })
    if ($c.Count -eq 0) { return $null }
    try { return ($c[-1] | ConvertFrom-Json) } catch { return $null }
}

try {
    $driftArgs = @('-Json')
    if ($Strict) { $driftArgs += '-Strict' }
    $lines = @(& pwsh -NoProfile -WorkingDirectory $RepoRoot -File (Join-Path $RepoRoot 'tools/verify-skills-drift.ps1') @driftArgs 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $o = Get-LastJsonObjectFromLines -Lines $lines
    $driftSt = if ($o) { [string]$o.status } else { if ($code -eq 0) { 'ok' } else { 'fail' } }
    if ($code -ne 0 -and $driftSt -ne 'fail') { $driftSt = 'fail' }
    [void]$checks.Add([ordered]@{ name = 'skills_body_drift'; status = $driftSt; detail = 'delegated verify-skills-drift' })
    if ($driftSt -eq 'fail') { [void]$failures.Add('verify-skills-drift reported fail or non-zero exit') }
    elseif ($driftSt -eq 'warn') { [void]$warnings.Add('verify-skills-drift reported warn (drift or missing copies)') }

    $mfPath = Join-Path $RepoRoot 'skills-manifest.json'
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json
    foreach ($sk in @($mf.skills)) {
        foreach ($gt in @($sk.generatedTargets | ForEach-Object { [string]$_ })) {
            if ($gt -notmatch '\.md$') { continue }
            $genFull = Join-Path $RepoRoot ($gt.TrimStart('/', '\') -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $genFull)) { continue }
            $head = (Get-Content -LiteralPath $genFull -TotalCount 1 -Encoding utf8)
            if ($head -notmatch '^\s*<!--\s*Generated from\s+source/skills/') {
                $msg = "missing generation header: $gt (skill $($sk.id))"
                if ($Strict) { [void]$failures.Add($msg) }
                else { [void]$warnings.Add($msg) }
                [void]$findings.Add([ordered]@{ skill = [string]$sk.id; target = $gt; marker = 'missing' })
            }
            else {
                [void]$findings.Add([ordered]@{ skill = [string]$sk.id; target = $gt; marker = 'ok' })
            }
        }
    }

    $aaPath = Join-Path $RepoRoot 'agent-adapters-manifest.json'
    $aa = Get-Content -LiteralPath $aaPath -Raw | ConvertFrom-Json
    $schPath = Join-Path $RepoRoot 'schemas/generated-target.schema.json'
    if (-not (Test-Path -LiteralPath $schPath)) {
        [void]$failures.Add('missing schemas/generated-target.schema.json')
    }
    foreach ($t in @($aa.generatedTargets)) {
        if (-not $t.path -or -not $t.source) {
            [void]$failures.Add('agent-adapters-manifest.generatedTargets entry missing path or source')
            continue
        }
        $p = [string]$t.path
        if ($p -match 'source/skills') {
            [void]$failures.Add("generatedTargets must not point into canonical source: $p")
        }
    }

    [void]$checks.Add([ordered]@{ name = 'generated_target_manifest'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'agent-adapters generatedTargets shape' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
if ($Strict -and $warnings.Count -gt 0) { $st = 'fail' }
$env = New-OsValidatorEnvelope -Tool 'verify-generated-drift' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-generated-drift: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
if ($Strict) { if ($warnings.Count -gt 0) { exit 1 } }
exit 0
