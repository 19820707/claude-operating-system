# verify-skills-economy.ps1 — Per-skill context bounds + hygiene (no secrets, no Arcads domain leakage heuristics)
#   pwsh ./tools/verify-skills-economy.ps1 [-Json]

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

$arcadsHints = @(
    '(?i)\bUGC\b',
    '(?i)\bArcads\b',
    '(?i)video\s*generation',
    '(?i)model\s*credits?'
)

# Unsafe false-green phrasing in operational skills (must not equate non-pass states with pass).
$falseGreenPatterns = @(
    @{ re = '(?i)skipped\s*=\s*passed'; msg = 'unsafe: skipped = passed' }
    @{ re = '(?i)skip\s*=\s*pass(ed)?\b'; msg = 'unsafe: skip equated to pass' }
    @{ re = '(?i)warn(ing)?\s*=\s*pass'; msg = 'unsafe: warn = pass' }
    @{ re = '(?i)unknown\s*=\s*pass'; msg = 'unsafe: unknown = pass' }
    @{ re = '(?i)degraded\s*=\s*pass'; msg = 'unsafe: degraded = pass' }
    @{ re = '(?i)blocked\s*=\s*pass'; msg = 'unsafe: blocked = pass' }
)

try {
    $mfPath = Join-Path $RepoRoot 'skills-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing skills-manifest.json' }
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    foreach ($sk in @($mf.skills)) {
        $rel = [string]$sk.path
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($raw)
        $lines = @($raw -split "`n").Count
        $cb = $sk.contextBudget
        $maxB = [int]$cb.maxBytes
        $maxL = [int]$cb.maxLines
        if ($bytes -gt $maxB) {
            [void]$failures.Add("$rel exceeds manifest contextBudget.maxBytes ($bytes > $maxB)")
        }
        if ($lines -gt $maxL) {
            [void]$failures.Add("$rel exceeds manifest contextBudget.maxLines ($lines > $maxL)")
        }

        foreach ($h in $arcadsHints) {
            if ($raw -match $h) {
                [void]$warnings.Add("$rel matches external-product heuristic ($h) — verify wording is generic")
            }
        }
        if ($raw -match '(?i)Bearer\s+[A-Za-z0-9._-]{20,}') {
            [void]$failures.Add("$rel may contain bearer-token-like material")
        }

        foreach ($fg in $falseGreenPatterns) {
            if ($raw -match $fg.re) {
                [void]$failures.Add("$rel : $($fg.msg)")
            }
        }

        [void]$findings.Add([ordered]@{ skill = [string]$sk.id; lines = $lines; bytes = $bytes; maxLines = $maxL; maxBytes = $maxB })
    }

    [void]$checks.Add([ordered]@{ name = 'skills-economy'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'per-skill contextBudget + hygiene' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-skills-economy' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-skills-economy: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
