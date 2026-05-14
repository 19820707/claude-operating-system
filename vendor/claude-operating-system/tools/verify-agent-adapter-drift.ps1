# verify-agent-adapter-drift.ps1 — Uncommitted edits under templates/adapters and optional generatedTargets (manifest-driven)
#   pwsh ./tools/verify-agent-adapter-drift.ps1 [-Json] [-FailOnDrift]
# Without Git: warn + skip (cannot prove cleanliness). -FailOnDrift upgrades dirty tree to fail.

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$FailOnDrift
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

function Add-DriftFinding {
    param(
        [string]$Path,
        [string]$Severity,
        [string]$Detail
    )
    [void]$script:findings.Add([ordered]@{ path = $Path; severity = $Severity; detail = $Detail })
}

function Invoke-GitPorcelain {
    param([string]$RelativePath)
    Push-Location $RepoRoot
    try {
        $norm = $RelativePath.TrimStart('/', '\') -replace '/', [char][System.IO.Path]::DirectorySeparatorChar
        return (& git status --porcelain -- $norm 2>$null | Out-String).Trim()
    }
    finally {
        Pop-Location
    }
}

function Test-PathUnderRepo {
    param([string]$RelativePath)
    $norm = $RelativePath.TrimStart('/', '\') -replace '/', [char][System.IO.Path]::DirectorySeparatorChar
    $full = Join-Path $RepoRoot $norm
    return (Test-Path -LiteralPath $full)
}

try {
    $rootGit = Join-Path $RepoRoot '.git'
    if (-not (Test-Path -LiteralPath $rootGit)) {
        [void]$warnings.Add('no .git: drift checks skipped (cannot run git status)')
        [void]$checks.Add([ordered]@{ name = 'adapter-drift'; status = 'skip'; detail = 'no git checkout' })
    }
    else {
        Push-Location $RepoRoot
        try {
            $targets = [System.Collections.Generic.List[string]]::new()
            [void]$targets.Add('templates/adapters')

            $mfPath = Join-Path $RepoRoot 'agent-adapters-manifest.json'
            if (Test-Path -LiteralPath $mfPath) {
                $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json
                if ($mf.PSObject.Properties.Name -contains 'generatedTargets') {
                    foreach ($gt in @($mf.generatedTargets)) {
                        $p = [string]$gt.path
                        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-PathUnderRepo -RelativePath $p)) {
                            [void]$targets.Add(($p.TrimStart('/', '\') -replace '\\', '/'))
                        }
                    }
                }
            }

            foreach ($rel in @($targets | Select-Object -Unique)) {
                $gitPath = [string]$rel -replace '\\', '/'
                $dirty = Invoke-GitPorcelain -RelativePath $gitPath
                if ($dirty) {
                    $msg = "$gitPath has uncommitted changes vs HEAD"
                    if ($FailOnDrift) {
                        [void]$failures.Add($msg)
                        Add-DriftFinding -Path $gitPath -Severity 'fail' -Detail $msg
                    }
                    else {
                        [void]$warnings.Add($msg)
                        Add-DriftFinding -Path $gitPath -Severity 'warn' -Detail $msg
                    }
                }
                else {
                    Add-DriftFinding -Path $gitPath -Severity 'ok' -Detail 'clean vs HEAD'
                }
            }
        }
        finally {
            Pop-Location
        }
        [void]$checks.Add([ordered]@{
                name   = 'adapter-drift'
                status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
                detail = 'git porcelain on templates/adapters + existing generatedTargets paths'
            })
    }
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-agent-adapter-drift' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-agent-adapter-drift: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
