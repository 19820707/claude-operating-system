# sync-skills.ps1 — Copy canonical SKILL.md to declared generatedTargets (manifest-driven)
#   pwsh ./tools/sync-skills.ps1 [-Json] [-WhatIf]  (-WhatIf implies -DryRun)

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Json,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$copied = [System.Collections.Generic.List[string]]::new()
$unchanged = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()

$dry = [bool]($DryRun -or -not $PSCmdlet.ShouldProcess($RepoRoot, 'sync skills to generated targets'))

try {
    $mfPath = Join-Path $RepoRoot 'skills-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing skills-manifest.json' }
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json
    $headerTpl = "<!-- Generated from {0}. Do not edit this copy directly. Edit canonical source/skills/{1}/SKILL.md. -->`n"

    foreach ($sk in @($mf.skills)) {
        $src = Join-Path $RepoRoot ([string]$sk.path)
        if (-not (Test-Path -LiteralPath $src)) {
            [void]$failures.Add("missing canonical: $($sk.path)")
            continue
        }
        $canon = (Get-Content -LiteralPath $src -Raw -Encoding utf8) -replace "`r`n", "`n"
        $id = [string]$sk.id
        foreach ($gt in @($sk.generatedTargets | ForEach-Object { [string]$_ })) {
            if ($gt -match 'source/skills') {
                [void]$failures.Add("refuse to write into canonical path: $gt")
                continue
            }
            $dest = Join-Path $RepoRoot ($gt.TrimStart('/', '\') -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            $dir = Split-Path $dest -Parent
            $out = ($headerTpl -f ([string]$sk.path), $id) + $canon
            $expectedNorm = $out.TrimEnd()
            if ($dry) {
                if (-not (Test-Path -LiteralPath $dest)) {
                    [void]$copied.Add($gt)
                }
                else {
                    $cur = ((Get-Content -LiteralPath $dest -Raw -Encoding utf8) -replace "`r`n", "`n").TrimEnd()
                    if ($cur -eq $expectedNorm) {
                        [void]$unchanged.Add($gt)
                    }
                    else {
                        [void]$copied.Add($gt)
                    }
                }
                continue
            }
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $write = $true
            if (Test-Path -LiteralPath $dest) {
                $cur = ((Get-Content -LiteralPath $dest -Raw -Encoding utf8) -replace "`r`n", "`n").TrimEnd()
                if ($cur -eq $expectedNorm) {
                    [void]$unchanged.Add($gt)
                    $write = $false
                }
            }
            if ($write) {
                [System.IO.File]::WriteAllText($dest, $out, [System.Text.UTF8Encoding]::new($false))
                [void]$copied.Add($gt)
            }
        }
    }
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }

$env = [ordered]@{
    tool       = 'sync-skills'
    status     = $st
    durationMs = [int]$sw.ElapsedMilliseconds
    checks     = @(@{ name = 'sync'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'manifest generatedTargets' })
    warnings   = @($warnings)
    failures   = @($failures)
    findings   = @($findings)
    copied     = @($copied)
    unchanged  = @($unchanged)
    skipped    = @($skipped)
}

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "sync-skills: $($env.status) copied=$($copied.Count) unchanged=$($unchanged.Count) skipped=$($skipped.Count) dry=$dry"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
