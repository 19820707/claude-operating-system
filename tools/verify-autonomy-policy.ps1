# verify-autonomy-policy.ps1 — Validate policies/autonomy-policy.json contract (human-gated surfaces, no unsafe autonomy)
#   pwsh ./tools/verify-autonomy-policy.ps1 [-Json] [-Strict]

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

$requiredSurfaces = @(
    'production',
    'release_publish',
    'destructive_write',
    'migration',
    'incident_external_impact',
    'security_policy_change',
    'secret_handling',
    'validator_bypass',
    'policy_relaxation',
    'breaking_schema_change',
    'file_removal',
    'irreversible_action'
)

try {
    $path = Join-Path $RepoRoot 'policies/autonomy-policy.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'missing policies/autonomy-policy.json' }
    $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    if ([string]$j.defaultAutonomyLevel -eq 'A4') {
        [void]$failures.Add('defaultAutonomyLevel must not be A4 (closed loop forbidden as default)')
    }

    $surfaces = @($j.requiresHumanApproval.surfaces | ForEach-Object { [string]$_ })
    foreach ($s in $requiredSurfaces) {
        if ($surfaces -notcontains $s) {
            [void]$failures.Add("requiresHumanApproval.surfaces must include '$s'")
        }
    }

    $rules = $j.validationRules
    if (-not $rules) { throw 'missing validationRules' }
    foreach ($k in @('neverDowngradeFailToWarn', 'neverTreatSkippedValidationAsSuccess', 'neverBypassValidators', 'neverTreatNonOkEnvelopeAsSuccess')) {
        $pv = $rules.PSObject.Properties[$k]
        if (-not $pv -or [bool]$pv.Value -ne $true) {
            [void]$failures.Add("validationRules.$k must be true")
        }
    }

    $allowed = @($j.allowedAutonomousActions | ForEach-Object { [string]$_ })
    if ($allowed.Count -lt 1) { [void]$failures.Add('allowedAutonomousActions must be non-empty') }

    $forbiddenInAllowed = @($j.forbiddenPatternsInAllowedActions | ForEach-Object { [string]$_ })
    foreach ($a in $allowed) {
        $low = $a.ToLowerInvariant()
        foreach ($pat in $forbiddenInAllowed) {
            if ($low.Contains($pat.ToLowerInvariant())) {
                [void]$failures.Add("allowedAutonomousActions entry '$a' contains forbidden pattern '$pat'")
            }
        }
    }

    if ($Strict) {
        foreach ($a in $allowed) {
            $low = $a.ToLowerInvariant()
            if ($low -match 'publish|production|bypass|secret|migrate|destructive|delete|force|irreversible|relax|disable.?validator') {
                [void]$failures.Add("strict: allowedAutonomousActions must not imply steward/destructive/bypass semantics: '$a'")
            }
        }
        if ([string]$j.defaultAutonomyLevel -ne 'A3') {
            [void]$failures.Add('strict: defaultAutonomyLevel must be A3')
        }
        # Steward surfaces must never appear as autonomous-allowed tokens (would conflate approval with autonomy).
        foreach ($a in $allowed) {
            foreach ($s in $requiredSurfaces) {
                if ([string]$a -eq $s) {
                    [void]$failures.Add("strict: allowedAutonomousActions must not equal steward surface '$s' (critical/destructive/release-class actions require human approval, not autonomy list)")
                }
            }
        }
    }

    [void]$checks.Add([ordered]@{
            name   = 'autonomy-policy-parse'
            status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' })
            detail = 'policies/autonomy-policy.json'
        })
    [void]$findings.Add([ordered]@{ surfaces = $surfaces.Count; strict = [bool]$Strict })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-autonomy-policy' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-autonomy-policy: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
