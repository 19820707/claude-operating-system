# verify-skills-manifest.ps1 — skills-manifest.json contract (paths, policies, risk gates, deprecated vs release)
#   pwsh ./tools/verify-skills-manifest.ps1 [-Json] [-Strict]   # -Strict => deprecated-in-release + disk↔manifest are failures when applicable

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

try {
    $mfPath = Join-Path $RepoRoot 'skills-manifest.json'
    $schemaPath = Join-Path $RepoRoot 'schemas/skills-manifest.schema.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing skills-manifest.json' }
    if (-not (Test-Path -LiteralPath $schemaPath)) { throw 'missing schemas/skills-manifest.schema.json' }
    $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($sk in @($mf.skills)) {
        $id = [string]$sk.id
        if ($ids.Contains($id)) {
            [void]$failures.Add("duplicate skill id: $id")
            continue
        }
        [void]$ids.Add($id)

        $rel = [string]$sk.path
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            [void]$failures.Add("skill path missing: $rel")
        }
        if ($rel -notmatch 'source/skills/[a-z0-9-]+/SKILL\.md$') {
            [void]$failures.Add("skill path must be canonical source/skills/<id>/SKILL.md: $rel")
        }
        elseif ($rel -match '^source/skills/([a-z0-9-]+)/SKILL\.md$' -and $Matches[1] -ne $id) {
            [void]$failures.Add("skill $id path folder '$($Matches[1])' must match id")
        }

        foreach ($gt in @($sk.generatedTargets | ForEach-Object { [string]$_ })) {
            if ($gt -match 'source/skills') {
                [void]$failures.Add("generatedTargets must not point into canonical source: $gt")
            }
        }

        $ex = @($sk.examples | ForEach-Object { [string]$_ })
        $ts = @($sk.tests | ForEach-Object { [string]$_ })
        if ($ex.Count -eq 0 -and $ts.Count -eq 0) {
            $er = [string]$sk.examplesExemptionReason
            if ([string]::IsNullOrWhiteSpace($er)) {
                [void]$failures.Add("skill $id : examples/tests empty but examplesExemptionReason missing")
            }
        }
        foreach ($p in $ex) {
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $pf = Join-Path $RepoRoot $p
                if (-not (Test-Path -LiteralPath $pf)) { [void]$failures.Add("skill $id missing example file: $p") }
            }
        }
        foreach ($p in $ts) {
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $pf = Join-Path $RepoRoot $p
                if (-not (Test-Path -LiteralPath $pf)) { [void]$failures.Add("skill $id missing test file: $p") }
            }
        }

        foreach ($pol in @($sk.relatedPolicies | ForEach-Object { [string]$_ })) {
            if ([string]::IsNullOrWhiteSpace($pol)) { continue }
            $polFull = Join-Path $RepoRoot ($pol -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $polFull)) {
                [void]$failures.Add("skill $id relatedPolicies missing: $pol")
            }
        }

        $risk = [string]$sk.riskLevel
        $ap = @($sk.requiresApprovalFor | ForEach-Object { [string]$_ })
        if ($risk -in @('high', 'critical') -and $ap.Count -eq 0) {
            [void]$failures.Add("skill $id risk $risk must declare requiresApprovalFor (non-empty)")
        }

        if ([string]$sk.maturity -eq 'deprecated' -and [string]$sk.status -eq 'active') {
            [void]$failures.Add("deprecated skill $id must not have status active")
        }
    }

    $skillsRoot = Join-Path $RepoRoot 'source\skills'
    if (Test-Path -LiteralPath $skillsRoot) {
        foreach ($sd in @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)) {
            $dn = $sd.Name
            if (-not $ids.Contains($dn)) {
                [void]$failures.Add("source/skills/$dn exists on disk but has no skills-manifest.json entry")
            }
        }
    }

    $rpPath = Join-Path $RepoRoot 'runtime-profiles.json'
    if (Test-Path -LiteralPath $rpPath) {
        $rp = Get-Content -LiteralPath $rpPath -Raw | ConvertFrom-Json
        $releaseIds = @('strict')
        if ($mf.PSObject.Properties.Name -contains 'releaseProfileIds') {
            $releaseIds = @($mf.releaseProfileIds | ForEach-Object { [string]$_ })
        }
        foreach ($sk in @($mf.skills)) {
            if ([string]$sk.maturity -ne 'deprecated') { continue }
            foreach ($prof in @($rp.profiles)) {
                if ($releaseIds -notcontains [string]$prof.id) { continue }
                $blob = ($prof | ConvertTo-Json -Depth 6 -Compress)
                if ($blob -match [regex]::Escape([string]$sk.id)) {
                    $msg = "deprecated skill $($sk.id) referenced in release-like profile $($prof.id)"
                    if ($Strict) {
                        [void]$failures.Add($msg)
                    }
                    else {
                        [void]$warnings.Add("$msg (verify manually)")
                    }
                }
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'skills-manifest'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'skills-manifest.json' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-skills-manifest' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-skills-manifest: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
