# verify-skills-structure.ps1 — Canonical SKILL.md section contract (manifest-driven)
#   pwsh ./tools/verify-skills-structure.ps1 [-Json] [-Strict]

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

$requiredStable = @(
    @{ n = 'Purpose'; alt = @('(?m)^#\s+', '##\s+Purpose') }
    @{ n = 'Non-goals'; alt = @('##\s+Non-goals') }
    @{ n = 'Inputs'; alt = @('##\s+Inputs') }
    @{ n = 'Outputs'; alt = @('##\s+Outputs') }
    @{ n = 'Operating mode'; alt = @('##\s+Operating mode', '##\s+Operating contract') }
    @{ n = 'Procedure'; alt = @('##\s+Procedure', '##\s+Operating contract', '##\s+Surgical mode') }
    @{ n = 'Validation'; alt = @('##\s+Validation', '##\s+Required checks') }
    @{ n = 'Failure modes'; alt = @('##\s+Failure modes') }
    @{ n = 'Safety rules'; alt = @('##\s+Safety rules', '##\s+No-false-green', '##\s+Invariants') }
    @{ n = 'Examples'; alt = @('##\s+Examples', '##\s+Minimal examples') }
    @{ n = 'Related files'; alt = @('##\s+Related files') }
)

try {
    $mfPath = Join-Path $RepoRoot 'skills-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing skills-manifest.json' }
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    foreach ($sk in @($mf.skills)) {
        $rel = [string]$sk.path
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $body = Get-Content -LiteralPath $full -Raw
        $maturity = [string]$sk.maturity
        $risk = [string]$sk.riskLevel
        $id = [string]$sk.id

        foreach ($sec in $requiredStable) {
            $ok = $false
            foreach ($pat in $sec.alt) {
                if ($body -match $pat) { $ok = $true; break }
            }
            if (-not $ok) {
                if ($Strict -and $maturity -eq 'stable') {
                    [void]$failures.Add("skill $id missing section $($sec.n) ($rel)")
                }
                else {
                    [void]$warnings.Add("skill $id missing recommended section $($sec.n) (use SKILL.template.md)")
                }
            }
        }

        if ($maturity -eq 'stable' -and $risk -in @('high', 'critical')) {
            if ($body -notmatch '##\s+Safety rules') {
                [void]$failures.Add("skill $id stable+$risk must include explicit ## Safety rules section ($rel)")
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'skills-structure'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'SKILL.md headings' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-skills-structure' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-skills-structure: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
