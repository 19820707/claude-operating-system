# os-validate-all.ps1 — Release-grade aggregate validation
# Run from repo root:
#   pwsh ./tools/os-validate-all.ps1
#   pwsh ./tools/os-validate-all.ps1 -Strict
#   pwsh ./tools/os-validate-all.ps1 -Strict -Json   # compact machine-readable summary

param(
    [switch]$Strict,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash,
    [switch]$Json,
    [switch]$WriteHistory
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failures = @()
$script:JsonMode = [bool]$Json
$script:ValidateRecords = [System.Collections.Generic.List[object]]::new()
$script:ValidateHealthEnvelope = $null

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
        $script:ValidateRecords.Add([pscustomobject]@{ name = $Name; status = 'ok'; latencyMs = $ms; detail = '' })
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
            $_.status -eq 'warn' -and $_.name -notin $allowedWarnings -and $_.name -notlike 'scaffold:*' -and $_.name -notlike 'git:*'
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
                    '.agent/operating-contract.md',
                    '.agents/OPERATING_CONTRACT.md'
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
    $failN = @($script:ValidateRecords | Where-Object { $_.status -eq 'fail' }).Count
    $warnN = @($script:ValidateRecords | Where-Object { $_.status -eq 'warn' }).Count
    $failedNames = @(
        @($script:ValidateRecords | Where-Object { $_.status -eq 'fail' } | ForEach-Object { [string]$_.name }) | Select-Object -First 16
    )
    $diag = [System.Collections.Generic.List[string]]::new()
    if ($failedNames -contains 'health') {
        $hb = if ($script:EffectiveSkipBashSyntax) { ' -SkipBashSyntax' } else { '' }
        [void]$diag.Add("pwsh ./tools/verify-os-health.ps1 -Json$hb")
        [void]$diag.Add('pwsh ./tools/verify-git-hygiene.ps1 -Json')
    }
    if ($failedNames -contains 'doctor') {
        $db = if ($script:EffectiveSkipBashSyntax) { ' -SkipBashSyntax' } else { '' }
        [void]$diag.Add("pwsh ./tools/os-doctor.ps1 -Json$db")
    }
    if ($failedNames -contains 'json-contracts') { [void]$diag.Add('pwsh ./tools/verify-json-contracts.ps1') }
    if ($failedNames -contains 'examples') { [void]$diag.Add('pwsh ./tools/verify-examples.ps1') }
    if ($failedNames -contains 'bootstrap-examples') { [void]$diag.Add('pwsh ./tools/verify-bootstrap-examples.ps1') }
    if ($failedNames -contains 'generated-project-tools') { [void]$diag.Add('pwsh ./tools/os-validate-all.ps1 -Strict (see init-project logs above)') }
    if ($failedNames -contains 'session-memory-cycle') { [void]$diag.Add('pwsh ./tools/verify-session-memory.ps1') }

    $checkObjs = foreach ($r in $script:ValidateRecords) {
        $d = if ($null -eq $r.detail) { '' } else { [string]$r.detail }
        [ordered]@{
            name      = [string]$r.name
            status    = [string]$r.status
            latencyMs = [int]$r.latencyMs
            detail    = (Redact-SensitiveText -Text $d -MaxLength 220)
        }
    }
    $fmsg = if ($failN -gt 0) {
        Redact-SensitiveText -Text ("Validation failed ($failN): " + ($failedNames -join ', ')) -MaxLength 400
    } else { '' }

    $healthSummary = $null
    if ($null -ne $script:ValidateHealthEnvelope) {
        $h = $script:ValidateHealthEnvelope
        $healthSummary = [ordered]@{
            status   = [string]$h.status
            failures = [int]$h.failures
            warnings = [int]$h.warnings
            totalMs  = [int]$h.totalMs
        }
    }

    $out = [ordered]@{
        name              = 'os-validate-all'
        status            = $Status
        strict            = [bool]$Strict
        checks            = @($checkObjs)
        warnings          = [int]$warnN
        failures          = [int]$failN
        failedChecks      = @($failedNames)
        failureMessage     = $fmsg
        suggestedCommands = @($diag)
        bash              = [ordered]@{
            available = [bool]$script:BashAvailable
            skipped   = [bool]$script:EffectiveSkipBashSyntax
            required  = [bool]$RequireBash
        }
        healthSummary     = $healthSummary
        repo              = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
    }
    $out | ConvertTo-Json -Depth 12 -Compress | Write-Output
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

function Invoke-HealthAggregate {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $hp = @{}
    if ($script:EffectiveSkipBashSyntax) { $hp['SkipBashSyntax'] = $true }
    elseif ($RequireBash) { $hp['RequireBash'] = $true }
    if ($Strict) { $hp['Strict'] = $true }
    if ($script:JsonMode) { $hp['Json'] = $true }
    if ($WriteHistory) { $hp['WriteHistory'] = $true }
    $cap = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($line in @(& (Join-Path $RepoRoot 'tools/verify-os-health.ps1') @hp 2>$null)) {
            [void]$cap.Add([string]$line)
        }
        $exitCode = $LASTEXITCODE
        $sw.Stop()
        if ($exitCode -ne 0) {
            $script:ValidateHealthEnvelope = $null
            if ($cap.Count -gt 0) {
                try { $script:ValidateHealthEnvelope = ($cap[$cap.Count - 1] | ConvertFrom-Json) } catch { }
            }
            $sum = if ($null -ne $script:ValidateHealthEnvelope -and $script:ValidateHealthEnvelope.status) {
                "aggregate status=$($script:ValidateHealthEnvelope.status)"
            } else {
                'verify-os-health returned non-zero exit code'
            }
            $script:ValidateRecords.Add([pscustomobject]@{ name = 'health'; status = 'fail'; latencyMs = [int]$sw.ElapsedMilliseconds; detail = $sum })
            if (-not $script:JsonMode) {
                Write-StatusLine -Status 'fail' -Name 'health' -Detail "$sum ($($sw.ElapsedMilliseconds) ms)"
            }
            $script:failures += 'health'
            return
        }
        if ($script:JsonMode -and $cap.Count -gt 0) {
            try { $script:ValidateHealthEnvelope = ($cap[$cap.Count - 1] | ConvertFrom-Json) } catch { $script:ValidateHealthEnvelope = $null }
        }
        $aggSt = 'ok'
        if ($null -ne $script:ValidateHealthEnvelope) {
            if ($script:ValidateHealthEnvelope.status -eq 'fail') { $aggSt = 'fail' }
            elseif ($script:ValidateHealthEnvelope.status -eq 'warn') { $aggSt = 'warn' }
        }
        $detail = if ($script:JsonMode -and $null -ne $script:ValidateHealthEnvelope) {
            "aggregate status=$($script:ValidateHealthEnvelope.status)"
        } else { '' }
        $script:ValidateRecords.Add([pscustomobject]@{ name = 'health'; status = $aggSt; latencyMs = [int]$sw.ElapsedMilliseconds; detail = $detail })
        if ($aggSt -eq 'fail') { $script:failures += 'health' }
        if (-not $script:JsonMode) {
            Write-StatusLine -Status $(if ($aggSt -eq 'warn') { 'warn' } else { 'ok' }) -Name 'health' -Detail "$($sw.ElapsedMilliseconds) ms"
        }
    } catch {
        $sw.Stop()
        $msg = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 220
        if ($cap.Count -gt 0) {
            try { $script:ValidateHealthEnvelope = ($cap[$cap.Count - 1] | ConvertFrom-Json) } catch { }
        }
        $script:ValidateRecords.Add([pscustomobject]@{ name = 'health'; status = 'fail'; latencyMs = [int]$sw.ElapsedMilliseconds; detail = $msg })
        if (-not $script:JsonMode) {
            Write-StatusLine -Status 'fail' -Name 'health' -Detail "$msg ($($sw.ElapsedMilliseconds) ms)"
        }
        $script:failures += 'health'
    }
}

Invoke-HealthAggregate
Invoke-Validation -Name 'doctor' -Script { Invoke-DoctorStrict }
Invoke-Validation -Name 'json-contracts' -Script { & (Join-Path $RepoRoot 'tools/verify-json-contracts.ps1') }
Invoke-Validation -Name 'contract-tests' -Script { & (Join-Path $RepoRoot 'tools/run-contract-tests.ps1') }
Invoke-Validation -Name 'examples' -Script { & (Join-Path $RepoRoot 'tools/verify-examples.ps1') }
Invoke-Validation -Name 'bootstrap-examples' -Script { & (Join-Path $RepoRoot 'tools/verify-bootstrap-examples.ps1') }
Invoke-Validation -Name 'generated-project-tools' -Script { Test-GeneratedProjectTools }
Invoke-Validation -Name 'session-memory-cycle' -Script { Test-SessionMemoryCycle }

if (-not $Json) { Write-Host '' }

function Write-OsValidateAllHistory {
    param([string]$Status)
    if (-not $WriteHistory) { return }
    $wrn = @($script:ValidateRecords | Where-Object { $_.status -eq 'warn' } | ForEach-Object { [string]$_.name })
    $fl = @($script:ValidateRecords | Where-Object { $_.status -eq 'fail' } | ForEach-Object { [string]$_.name })
    $rec = [ordered]@{
        timestamp  = (Get-Date).ToUniversalTime().ToString('o')
        event      = 'validation'
        tool       = 'os-validate-all'
        profile    = $(if ($Strict) { 'strict' } else { 'release' })
        status     = $Status
        durationMs = [int](@($script:ValidateRecords | Measure-Object -Property latencyMs -Sum).Sum)
        warnings   = @($wrn)
        failures   = @($fl)
    }
    & (Join-Path $RepoRoot 'tools/write-validation-history.ps1') -Record ($rec | ConvertTo-Json -Depth 8 -Compress) -RepoRoot $RepoRoot -Quiet
}

$aggregateStatus = if ($failures.Count -gt 0) {
    'fail'
} elseif (@($script:ValidateRecords | Where-Object { $_.status -eq 'warn' }).Count -gt 0) {
    'warn'
} else {
    'ok'
}

if ($failures.Count -gt 0) {
    Write-OsValidateAllHistory -Status $aggregateStatus
    if ($Json) {
        Write-ValidateSummaryJson -Status $aggregateStatus
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
    if ($names -match 'examples') { $lines += '  pwsh ./tools/verify-examples.ps1' }
    if ($names -match 'bootstrap-examples') { $lines += '  pwsh ./tools/verify-bootstrap-examples.ps1' }
    if ($names -match 'generated-project-tools') { $lines += '  pwsh ./tools/os-validate-all.ps1 -Strict (see init-project + temp project logs above)' }
    if ($names -match 'session-memory-cycle') { $lines += '  pwsh ./tools/verify-session-memory.ps1' }
    throw ($lines -join "`n")
}

if ($Json) {
    Write-OsValidateAllHistory -Status $aggregateStatus
    Write-ValidateSummaryJson -Status $aggregateStatus
    exit 0
}

Write-OsValidateAllHistory -Status $aggregateStatus
Write-Host 'All validation checks passed.'
