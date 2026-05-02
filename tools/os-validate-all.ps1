# os-validate-all.ps1 — Release-grade aggregate validation
# Run from repo root:
#   pwsh ./tools/os-validate-all.ps1
#   pwsh ./tools/os-validate-all.ps1 -Strict
#   pwsh ./tools/os-validate-all.ps1 -Strict -Json   # compact machine-readable summary

param(
    [switch]$Strict,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failures = @()
$script:JsonMode = [bool]$Json
$script:ValidateRecords = [System.Collections.Generic.List[object]]::new()

. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

function Invoke-Validation {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($script:JsonMode) {
            $ip = $InformationPreference
            $pp = $ProgressPreference
            $InformationPreference = 'SilentlyContinue'
            $ProgressPreference = 'SilentlyContinue'
            try {
                & $Script 1>$null 6>$null 5>$null 4>$null 2>&1 | Out-Null
            } finally {
                $InformationPreference = $ip
                $ProgressPreference = $pp
            }
        } else {
            & $Script
        }
        $sw.Stop()
        $ms = [int]$sw.ElapsedMilliseconds
        $script:ValidateRecords.Add([pscustomobject]@{ name = $Name; status = 'ok'; latencyMs = $ms })
        if (-not $script:JsonMode) {
            Write-StatusLine -Status 'ok' -Name $Name -Detail "$ms ms"
        }
    } catch {
        $sw.Stop()
        $ms = [int]$sw.ElapsedMilliseconds
        $msg = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 220
        $script:ValidateRecords.Add([pscustomobject]@{ name = $Name; status = 'fail'; latencyMs = $ms; detail = $msg })
        if (-not $script:JsonMode) {
            Write-StatusLine -Status 'fail' -Name $Name -Detail "$msg ($ms ms)"
        }
        $script:failures += $Name
    }
}

function Invoke-DoctorStrict {
    # Invariant: splat named switches — do not pass string '-Json' positionally (fragile vs $args).
    $doctorParams = @{ Json = $true }
    if ($script:EffectiveSkipBashSyntax) { $doctorParams['SkipBashSyntax'] = $true }
    if ($RequireBash) { $doctorParams['RequireBash'] = $true }
    $raw = & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @doctorParams
    if ($LASTEXITCODE -ne 0) { throw 'doctor failed' }
    $doctor = ($raw | Out-String) | ConvertFrom-Json
    if ($doctor.failures -gt 0) { throw "doctor reported $($doctor.failures) failure(s)" }
    if ($Strict) {
        $allowedWarnings = @('project-scaffold', 'node', 'npm', 'invariant-bundles')
        if ($script:EffectiveSkipBashSyntax) { $allowedWarnings += 'bash' }
        $unexpectedWarnings = @($doctor.checks | Where-Object {
            $_.status -eq 'warn' -and $_.name -notin $allowedWarnings -and $_.name -notlike 'scaffold:*'
        })
        if ($unexpectedWarnings.Count -gt 0) {
            $warnNames = @(
                $unexpectedWarnings | Select-Object -First 8 | ForEach-Object {
                    $n = [string]$_.name
                    if ($n.Length -gt 48) { $n.Substring(0, 45) + '...' } else { $n }
                }
            )
            $list = ($warnNames -join ', ')
            throw "strict mode: doctor reported $($unexpectedWarnings.Count) unexpected warning(s): $list"
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
            foreach ($rel in @(
                    'AGENTS.md',
                    '.cursor/rules/claude-os-runtime.mdc',
                    '.agent/runtime.md',
                    '.agent/handoff.md',
                    '.agent/operating-contract.md'
                )) {
                $p = Join-Path $target $rel
                if (-not (Test-Path -LiteralPath $p)) {
                    throw "bootstrap missing adapter artifact: $rel"
                }
            }
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

function Write-ValidateSummaryJson {
    param([string]$Status)
    $out = [ordered]@{
        status  = $Status
        strict  = [bool]$Strict
        bash    = [ordered]@{
            available = [bool]$script:BashAvailable
            skipped   = [bool]$script:EffectiveSkipBashSyntax
            required  = [bool]$RequireBash
        }
        checks  = @($script:ValidateRecords)
        repo    = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
    }
    $out | ConvertTo-Json -Depth 8 -Compress | Write-Output
}

if (-not $Json) {
    Write-Host 'claude-operating-system validate-all'
    Write-Host "Repo  : $RepoRoot"
    Write-Host "Strict: $([bool]$Strict)"
}
# Invariant: bash syntax is optional locally unless -RequireBash; CI Ubuntu uses -RequireBash.
$script:BashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)
if ($RequireBash -and -not $script:BashAvailable) {
    if (-not $Json) {
        Write-Host 'Bash  : not found; required'
        Write-Host ''
    }
    throw 'os-validate-all: -RequireBash requires bash on PATH.'
}
$script:EffectiveSkipBashSyntax = [bool]($SkipBashSyntax -or ((-not $script:BashAvailable) -and -not $RequireBash))
if (-not $Json) {
    if ($script:BashAvailable) {
        Write-Host 'Bash  : available'
    } else {
        Write-Host 'Bash  : not found; syntax check auto-skipped'
    }
    Write-Host ''
}

Invoke-Validation -Name 'health' -Script {
    $hp = @{}
    if ($script:EffectiveSkipBashSyntax) { $hp['SkipBashSyntax'] = $true }
    elseif ($RequireBash) { $hp['RequireBash'] = $true }
    if ($Strict) { $hp['Strict'] = $true }
    & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') @hp
}
Invoke-Validation -Name 'doctor' -Script { Invoke-DoctorStrict }
Invoke-Validation -Name 'json-contracts' -Script { & (Join-Path $RepoRoot 'tools/verify-json-contracts.ps1') }
Invoke-Validation -Name 'generated-project-tools' -Script { Test-GeneratedProjectTools }
Invoke-Validation -Name 'session-memory-cycle' -Script { Test-SessionMemoryCycle }

if (-not $Json) { Write-Host '' }

if ($failures.Count -gt 0) {
    if ($Json) {
        Write-ValidateSummaryJson -Status 'fail'
        exit 1
    }
    $names = $failures -join ', '
    $lines = @("Validation failed: $names", 'Isolated commands (repo root):')
    if ($names -match 'health') {
        $hb = if ($script:EffectiveSkipBashSyntax) { ' -SkipBashSyntax' } else { '' }
        $lines += "  pwsh ./tools/verify-os-health.ps1$hb"
        $lines += '  pwsh ./tools/verify-git-hygiene.ps1 -Json'
    }
    if ($names -match 'doctor') {
        $db = if ($script:EffectiveSkipBashSyntax) { ' -SkipBashSyntax' } else { '' }
        $lines += "  pwsh ./tools/os-doctor.ps1 -Json$db"
    }
    if ($names -match 'json-contracts') { $lines += '  pwsh ./tools/verify-json-contracts.ps1' }
    if ($names -match 'generated-project-tools') { $lines += '  pwsh ./tools/os-validate-all.ps1 -Strict (see init-project + temp project logs above)' }
    if ($names -match 'session-memory-cycle') { $lines += '  pwsh ./tools/verify-session-memory.ps1' }
    throw ($lines -join "`n")
}

if ($Json) {
    Write-ValidateSummaryJson -Status 'ok'
    exit 0
}

Write-Host 'All validation checks passed.'
