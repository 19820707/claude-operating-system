# policy-completeness.ps1 — Policy-to-verifier coverage: every policy must have enforcement
# Governance theatre detector: policies without verifiers are wishes, not constraints.
# Scans policies/*.md and .claude/policies/*.md; checks for verify-*.ps1 counterparts.
#   pwsh ./tools/policy-completeness.ps1
#   pwsh ./tools/policy-completeness.ps1 -Json
#   pwsh ./tools/policy-completeness.ps1 -Strict   # fail if coverage < 80%

param(
    [double]$MinCoverage = 0.15,   # fail if coverage below this (warn between 0.15 and 0.60)
    [switch]$Strict,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw       = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

# ── Collect all policy files ──────────────────────────────────────────────────

$policyFiles = [System.Collections.Generic.List[string]]::new()
foreach ($dir in @('policies', '.claude/policies')) {
    $full = Join-Path $RepoRoot $dir
    if (Test-Path -LiteralPath $full) {
        Get-ChildItem -LiteralPath $full -Filter '*.md' -File | ForEach-Object {
            [void]$policyFiles.Add($_.FullName)
        }
    }
}

[void]$checks.Add([ordered]@{ name = 'policy-scan'; status = 'ok'; detail = "$($policyFiles.Count) policy file(s)" })

# ── Build verifier index ──────────────────────────────────────────────────────
# verifier name = stem of tools/verify-*.ps1 without 'verify-' prefix

$toolsDir = Join-Path $RepoRoot 'tools'
$verifierIndex = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

Get-ChildItem -LiteralPath $toolsDir -Filter 'verify-*.ps1' -File | ForEach-Object {
    # e.g. verify-security-policy → security-policy
    $slug = $_.BaseName -replace '^verify-', ''
    [void]$verifierIndex.Add($slug)
}
[void]$checks.Add([ordered]@{ name = 'verifier-index'; status = 'ok'; detail = "$($verifierIndex.Count) verify-*.ps1 found" })

# ── Load os-validate-all to check wiring ─────────────────────────────────────

$validateAllContent = ''
$validateAllPath = Join-Path $toolsDir 'os-validate-all.ps1'
if (Test-Path -LiteralPath $validateAllPath) {
    $validateAllContent = Get-Content -LiteralPath $validateAllPath -Raw -Encoding utf8
}
$validateContent = ''
$validatePath = Join-Path $toolsDir 'os-validate.ps1'
if (Test-Path -LiteralPath $validatePath) {
    $validateContent = Get-Content -LiteralPath $validatePath -Raw -Encoding utf8
}

# ── Evaluate each policy ──────────────────────────────────────────────────────

$rows = [System.Collections.Generic.List[object]]::new()

foreach ($pFile in $policyFiles) {
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($pFile)
    $relDir   = if ($pFile -match '[\\/]\.claude[\\/]') { '.claude/policies' } else { 'policies' }

    # Attempt to match the policy slug to a verifier
    # Direct match: security-policy.md → verify-security-policy.ps1
    $directMatch = $verifierIndex.Contains($fileName)

    # Fuzzy: strip common suffixes, try partial names
    $slug2 = $fileName -replace '-policy$', '' -replace '-contract$', '' -replace '-governance$', ''
    $fuzzyMatch = $verifierIndex.Contains($slug2) -or ($verifierIndex | Where-Object { $_ -match $slug2 })

    $hasVerifier = $directMatch -or $fuzzyMatch
    $verifierName = if ($directMatch) { "verify-$fileName.ps1" } elseif ($fuzzyMatch) { "verify-$slug2.ps1 (fuzzy)" } else { '' }

    # Check if wired into os-validate or os-validate-all
    $wired = $false
    if ($hasVerifier) {
        $toolName = if ($directMatch) { "verify-$fileName" } else { "verify-$slug2" }
        $wired = ($validateAllContent -match [regex]::Escape($toolName)) -or
                 ($validateContent    -match [regex]::Escape($toolName))
    }

    $coverage = if ($hasVerifier -and $wired) { 'full' } elseif ($hasVerifier) { 'partial' } else { 'none' }

    [void]$rows.Add([ordered]@{
        policy    = "$relDir/$fileName.md"
        verifier  = $verifierName
        wired     = $wired
        coverage  = $coverage
    })

    if (-not $hasVerifier) {
        [void]$warnings.Add("Policy without verifier: $relDir/$fileName.md — governance theatre risk")
    } elseif (-not $wired) {
        [void]$warnings.Add("Policy has verifier but it's not wired into os-validate: $verifierName")
    }
}

# ── Compute coverage score ────────────────────────────────────────────────────

$total   = $rows.Count
$full    = @($rows | Where-Object { $_.coverage -eq 'full' }).Count
$partial = @($rows | Where-Object { $_.coverage -eq 'partial' }).Count
$none    = @($rows | Where-Object { $_.coverage -eq 'none' }).Count

# Weighted: full=1.0 partial=0.5 none=0.0
$coverageScore = if ($total -gt 0) { [Math]::Round(($full + $partial * 0.5) / $total, 4) } else { 0.0 }
$coveragePct   = [Math]::Round($coverageScore * 100, 1)

[void]$checks.Add([ordered]@{ name = 'coverage'; status = 'ok'; detail = "full=$full partial=$partial none=$none coverage=$coveragePct%" })

if ($coverageScore -lt $MinCoverage) {
    [void]$failures.Add("Policy coverage $coveragePct% below minimum $([Math]::Round($MinCoverage*100,0))% — $none polic$(if ($none -ne 1){'ies'}else{'y'}) without any verifier")
} elseif ($Strict -and $none -gt 0) {
    [void]$failures.Add("Strict mode: $none polic$(if ($none -ne 1){'ies'}else{'y'}) without verifier — all policies must have enforcement")
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0 -or $partial -gt 0) { 'warn' } else { 'ok' }

$env = New-OsValidatorEnvelope -Tool 'policy-completeness' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        totalPolicies  = $total
        fullCoverage   = $full
        partialCoverage = $partial
        noCoverage     = $none
        coveragePct    = $coveragePct
        rows           = @($rows)
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
} else {
    Write-Host "policy-completeness | coverage=$coveragePct% | full=$full partial=$partial none=$none"
    Write-Host ''
    foreach ($r in $rows) {
        $icon = switch ($r.coverage) { 'full'{'OK'}; 'partial'{'~~'}; 'none'{'MISS'} }
        $wiredStr = if ($r.wired) { ' [wired]' } elseif ($r.verifier) { ' [verifier-only]' } else { '' }
        Write-Host "  [$icon] $($r.policy)$wiredStr$(if ($r.verifier){ "  → $($r.verifier)" })"
    }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
