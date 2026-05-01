# os-validate-all.ps1 — Release-grade aggregate validation
# Run from repo root:
#   pwsh ./tools/os-validate-all.ps1
#   pwsh ./tools/os-validate-all.ps1 -Strict

param(
    [switch]$Strict,
    [switch]$SkipBashSyntax
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failures = @()

. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

function Invoke-Validation {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Script
        $sw.Stop()
        Write-StatusLine -Status 'ok' -Name $Name -Detail "$([int]$sw.ElapsedMilliseconds) ms"
    } catch {
        $sw.Stop()
        $msg = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 220
        Write-StatusLine -Status 'fail' -Name $Name -Detail "$msg ($([int]$sw.ElapsedMilliseconds) ms)"
        $script:failures += $Name
    }
}

function Invoke-DoctorStrict {
    $raw = & (Join-Path $RepoRoot 'tools/os-doctor.ps1') -Json
    if ($LASTEXITCODE -ne 0) { throw 'doctor failed' }
    $doctor = ($raw | Out-String) | ConvertFrom-Json
    if ($doctor.failures -gt 0) { throw "doctor reported $($doctor.failures) failure(s)" }
    if ($Strict -and $doctor.warnings -gt 0) { throw "strict mode: doctor reported $($doctor.warnings) warning(s)" }
}

function Test-GeneratedProjectTools {
    $target = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-os-validate-' + [System.Guid]::NewGuid().ToString('N'))
    try {
        & (Join-Path $RepoRoot 'init-project.ps1') -ProjectPath $target -SkipGitInit | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'init-project failed' }

        $checks = @(
            @{ name = 'project-docs-query'; cmd = '.claude/scripts/query-docs-index.ps1'; args = @('-Query', 'health', '-Limit', '1', '-Json') },
            @{ name = 'project-capability-route'; cmd = '.claude/scripts/route-capability.ps1'; args = @('-Query', 'security', '-Limit', '1', '-Json') },
            @{ name = 'project-workflow-status'; cmd = '.claude/scripts/workflow-status.ps1'; args = @('-Phase', 'verify', '-Json') }
        )

        Push-Location $target
        try {
            foreach ($check in $checks) {
                $out = & pwsh $check.cmd @($check.args)
                if ($LASTEXITCODE -ne 0) { throw "$($check.name) returned non-zero" }
                $json = ($out | Out-String) | ConvertFrom-Json
                if (-not $json) { throw "$($check.name) produced invalid JSON" }
            }
        } finally {
            Pop-Location
        }
    } finally {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host 'claude-operating-system validate-all'
Write-Host "Repo  : $RepoRoot"
Write-Host "Strict: $([bool]$Strict)"
Write-Host ''

Invoke-Validation -Name 'health' -Script {
    if ($SkipBashSyntax) {
        & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') -SkipBashSyntax
    } else {
        & (Join-Path $RepoRoot 'tools/verify-os-health.ps1')
    }
}
Invoke-Validation -Name 'doctor' -Script { Invoke-DoctorStrict }
Invoke-Validation -Name 'json-contracts' -Script { & (Join-Path $RepoRoot 'tools/verify-json-contracts.ps1') }
Invoke-Validation -Name 'generated-project-tools' -Script { Test-GeneratedProjectTools }

Write-Host ''
if ($failures.Count -gt 0) {
    throw "Validation failed: $($failures -join ', ')"
}

Write-Host 'All validation checks passed.'
