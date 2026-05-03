# verify-skills-drift.ps1 — Canonical SKILL.md vs declared generated copies (manifest-driven)
#   pwsh ./tools/verify-skills-drift.ps1 [-Json] [-Strict]   # -Strict => drift is fail

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

function Strip-GeneratedHeader {
    param([string]$Text)
    $lines = @($Text -split "`r?`n")
    if ($lines.Count -gt 0 -and $lines[0] -match '^\s*<!--\s*Generated from source/skills/') {
        return ($lines | Select-Object -Skip 1 | ForEach-Object { $_ }) -join "`n"
    }
    return $Text
}

function Normalize-SkillBody {
    param([string]$Text)
    return (($Text -replace "`r`n", "`n").Trim())
}

try {
    $mfPath = Join-Path $RepoRoot 'skills-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing skills-manifest.json' }
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    foreach ($sk in @($mf.skills)) {
        $src = Join-Path $RepoRoot ([string]$sk.path)
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $canon = Get-Content -LiteralPath $src -Raw -Encoding utf8
        $canonN = Normalize-SkillBody -Text $canon
        foreach ($gt in @($sk.generatedTargets | ForEach-Object { [string]$_ })) {
            $genFull = Join-Path $RepoRoot ($gt.TrimStart('/', '\') -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $genFull)) {
                if ($Strict) {
                    [void]$failures.Add("missing generated copy: $gt (skill $($sk.id))")
                }
                [void]$findings.Add([ordered]@{ skill = [string]$sk.id; target = $gt; status = 'absent' })
                continue
            }
            $genRaw = Get-Content -LiteralPath $genFull -Raw -Encoding utf8
            $genNorm = Normalize-SkillBody -Text (Strip-GeneratedHeader -Text $genRaw)
            if ($genNorm -ne $canonN) {
                $msg = "drift: $gt differs from $($sk.path)"
                if ($Strict) {
                    [void]$failures.Add($msg)
                }
                else {
                    [void]$warnings.Add($msg)
                }
                [void]$findings.Add([ordered]@{ skill = [string]$sk.id; target = $gt; status = 'drift' })
            }
            else {
                [void]$findings.Add([ordered]@{ skill = [string]$sk.id; target = $gt; status = 'match' })
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'skills-drift'; status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }); detail = 'canonical vs generatedTargets when present' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-skills-drift' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-skills-drift: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
