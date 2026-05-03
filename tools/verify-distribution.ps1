# verify-distribution.ps1 — Validate distribution-manifest against repo and packaging rules (read-only)
#   pwsh ./tools/verify-distribution.ps1 [-Json]

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')
. (Join-Path $RepoRoot 'tools/lib/distribution-resolve.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

try {
    $mf = Import-DistributionManifest -Root $RepoRoot

    foreach ($rx in @($mf.excludePathRegexes | ForEach-Object { [string]$_ })) {
        if ([string]::IsNullOrWhiteSpace($rx)) {
            [void]$failures.Add('excludePathRegexes contains empty entry')
            continue
        }
        try {
            $null = [regex]::new($rx, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        catch {
            [void]$failures.Add("invalid excludePathRegex: $rx")
        }
    }

    foreach ($rf in @($mf.rootFiles | ForEach-Object { [string]$_ })) {
        $p = Join-Path $RepoRoot ($rf -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $p)) {
            [void]$failures.Add("rootFile missing on disk: $rf")
        }
    }

    $files = [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Get-DistributionPackagedRelativePaths -RepoRoot $RepoRoot -Manifest $mf),
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($mp in @($mf.mandatoryPackagedPaths | ForEach-Object { [string]$_ })) {
        $norm = $mp.Replace('\', '/')
        if (-not $files.Contains($norm)) {
            [void]$failures.Add("mandatoryPackagedPaths not in resolved pack list: $mp")
            [void]$findings.Add([ordered]@{ rule = 'missing-mandatory'; path = $norm })
        }
    }

    $toolPs1 = @($files | Where-Object { $_ -like 'tools/*.ps1' -and $_ -notlike 'tools/lib/*' }).Count
    if ($toolPs1 -lt 30) {
        [void]$warnings.Add("unexpectedly few tools/*.ps1 in pack ($toolPs1); verify includeTrees/tools")
    }

    [void]$checks.Add([ordered]@{
            name   = 'distribution-manifest'
            status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
            detail = "resolved $($files.Count) packaged paths"
        })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-distribution' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "verify-distribution: $($env.status)"
    foreach ($f in @($env.failures)) { Write-Host "FAIL: $f" }
    foreach ($w in @($env.warnings)) { Write-Host "WARN: $w" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
