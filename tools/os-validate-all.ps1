# os-validate-all.ps1 — Release-grade aggregate validation
# Run from repo root:
#   pwsh ./tools/os-validate-all.ps1
#   pwsh ./tools/os-validate-all.ps1 -Strict

param(
    [switch]$Strict,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failures = @()

. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

$BashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)
$EffectiveSkipBashSyntax = [bool]($SkipBashSyntax -or (-not $BashAvailable -and -not $RequireBash))

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
    $doctorArgs = @('-Json')
    if ($EffectiveSkipBashSyntax) { $doctorArgs += '-SkipBashSyntax' }
    $raw = & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @doctorArgs
    if ($LASTEXITCODE -ne 0) { throw 'doctor failed' }
    $doctor = ($raw | Out-String) | ConvertFrom-Json
    if ($doctor.failures -gt 0) { throw "doctor reported $($doctor.failures) failure(s)" }
    if ($Strict) {
        $allowedWarnings = @('project-scaffold','node','npm','invariant-bundles')
        if ($EffectiveSkipBashSyntax) { $allowedWarnings += 'bash' }
        $unexpectedWarnings = @($doctor.checks | Where-Object {
            $_.status -eq 'warn' -and $_.name -notin $allowedWarnings
        })
        if ($unexpectedWarnings.Count -gt 0) {
            throw "strict mode: doctor reported $($unexpectedWarnings.Count) unexpected warning(s)"
        }
    }
}

function New-BootstrappedTempProject {
    $target = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-os-validate-' + [System.Guid]::NewGuid().ToString('N'))
    & (Join-Path $RepoRoot 'init-project.ps1') -ProjectPath $target -SkipGitInit | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'init-project failed' }
    return $target
}

function Test-GeneratedProjectTools {
    $target = New-BootstrappedTempProject
    try {
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

function Test-SessionMemoryCycle {
    $target = New-BootstrappedTempProject
    try {
        Push-Location $target
        try {
            $prime = & pwsh '.claude/scripts/session-prime.ps1' -Json
            if ($LASTEXITCODE -ne 0) { throw 'session-prime returned non-zero' }
            $primeJson = ($prime | Out-String) | ConvertFrom-Json
            if (-not $primeJson.hasSessionState) { throw 'session-prime did not detect session-state' }

            & pwsh '.claude/scripts/session-absorb.ps1' -Note 'Runtime validation absorb smoke note' -Kind 'smoke' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'session-absorb returned non-zero' }

            & pwsh '.claude/scripts/session-digest.ps1' -Summary 'Runtime validation digest smoke summary' -Outcome 'passed' -Validation 'prime absorb digest smoke' -Next 'continue' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'session-digest returned non-zero' }

            $learning = Get-Content -LiteralPath '.claude/learning-log.md' -Raw
            if (-not $learning.Contains('Runtime validation absorb smoke note')) { throw 'absorb note missing from learning-log' }
            if (-not $learning.Contains('Runtime validation digest smoke summary')) { throw 'digest summary missing from learning-log' }

            $decision = Get-Content -LiteralPath '.claude/decision-log.jsonl' -Raw
            if (-not $decision.Contains('session-digest')) { throw 'digest record missing from decision-log' }
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
Write-Host "Bash  : $(if ($BashAvailable) { 'available' } elseif ($EffectiveSkipBashSyntax) { 'not found; syntax check auto-skipped' } else { 'not found; required' })"
Write-Host ''

Invoke-Validation -Name 'health' -Script {
    if ($EffectiveSkipBashSyntax) {
        & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') -SkipBashSyntax
    } else {
        & (Join-Path $RepoRoot 'tools/verify-os-health.ps1')
    }
}
Invoke-Validation -Name 'doctor' -Script { Invoke-DoctorStrict }
Invoke-Validation -Name 'json-contracts' -Script { & (Join-Path $RepoRoot 'tools/verify-json-contracts.ps1') }
Invoke-Validation -Name 'generated-project-tools' -Script { Test-GeneratedProjectTools }
Invoke-Validation -Name 'session-memory-cycle' -Script { Test-SessionMemoryCycle }

Write-Host ''
if ($failures.Count -gt 0) {
    throw "Validation failed: $($failures -join ', ')"
}

Write-Host 'All validation checks passed.'
