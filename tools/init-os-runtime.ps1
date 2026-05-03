# init-os-runtime.ps1 — Idempotent local runtime setup (workspace context, operator journal, dirs + optional health)
#   pwsh ./tools/init-os-runtime.ps1 [-Json] [-SkipBashSyntax] [-NoValidation] [-DryRun]

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$SkipBashSyntax,
    [switch]$NoValidation,
    [switch]$WriteHistory,
    [switch]$FullHealth,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$actions = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

try {
    $tpl = Join-Path $RepoRoot 'OS_WORKSPACE_CONTEXT.template.md'
    $ctx = Join-Path $RepoRoot 'OS_WORKSPACE_CONTEXT.md'
    if (-not (Test-Path -LiteralPath $tpl)) {
        [void]$failures.Add('missing OS_WORKSPACE_CONTEXT.template.md')
    }
    elseif (-not (Test-Path -LiteralPath $ctx)) {
        if ($DryRun) {
            [void]$actions.Add('[dry-run] would copy OS_WORKSPACE_CONTEXT.template.md -> OS_WORKSPACE_CONTEXT.md')
        }
        else {
            Copy-Item -LiteralPath $tpl -Destination $ctx
            [void]$actions.Add('created OS_WORKSPACE_CONTEXT.md from template')
        }
    }
    else {
        [void]$actions.Add('OS_WORKSPACE_CONTEXT.md already present (left unchanged)')
    }

    $journalTpl = Join-Path $RepoRoot 'OPERATOR_JOURNAL.template.md'
    $journalOut = Join-Path $RepoRoot 'OPERATOR_JOURNAL.md'
    if (-not (Test-Path -LiteralPath $journalTpl)) {
        [void]$failures.Add('missing OPERATOR_JOURNAL.template.md')
    }
    elseif (-not (Test-Path -LiteralPath $journalOut)) {
        if ($DryRun) {
            [void]$actions.Add('[dry-run] would copy OPERATOR_JOURNAL.template.md -> OPERATOR_JOURNAL.md')
        }
        else {
            Copy-Item -LiteralPath $journalTpl -Destination $journalOut
            [void]$actions.Add('created OPERATOR_JOURNAL.md from template')
        }
    }
    else {
        [void]$actions.Add('OPERATOR_JOURNAL.md already present (left unchanged)')
    }

    $logDir = Join-Path $RepoRoot 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        if ($DryRun) {
            [void]$actions.Add('[dry-run] would create directory logs/')
        }
        else {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            [void]$actions.Add('created logs/')
        }
    }
    else {
        [void]$actions.Add('logs/ already present')
    }

    $hasGit = Test-Path -LiteralPath (Join-Path $RepoRoot '.git')
    [void]$checks.Add([ordered]@{ name = 'git-checkout'; status = $(if ($hasGit) { 'ok' } else { 'warn' }); detail = $(if ($hasGit) { 'present' } else { 'missing .git' }) })

    $psv = $PSVersionTable.PSVersion.ToString()
    [void]$checks.Add([ordered]@{ name = 'powershell'; status = 'ok'; detail = $psv })

    $bash = [bool](Get-Command bash -ErrorAction SilentlyContinue)
    if (-not $bash -and -not $SkipBashSyntax) {
        [void]$warnings.Add('bash not on PATH (use -SkipBashSyntax on Windows for honest partial init)')
    }
    [void]$checks.Add([ordered]@{ name = 'bash'; status = $(if ($bash) { 'ok' } elseif ($SkipBashSyntax) { 'skip' } else { 'warn' }); detail = $(if ($bash) { 'available' } elseif ($SkipBashSyntax) { 'skipped by flag' } else { 'not found' }) })

    $sync = Join-Path $RepoRoot 'tools/sync-agent-adapters.ps1'
    if (Test-Path -LiteralPath $sync) {
        $sp = @{}
        if ($Json) { $sp['Json'] = $true }
        & $sync @sp
        if ($LASTEXITCODE -ne 0) {
            [void]$warnings.Add('sync-agent-adapters reported failure (non-blocking for init)')
        }
        else {
            [void]$actions.Add('sync-agent-adapters parity OK')
        }
    }

    if (-not $NoValidation) {
        if ($FullHealth) {
            $hp = @{}
            if ($SkipBashSyntax) { $hp['SkipBashSyntax'] = $true }
            if ($Json) { $hp['Json'] = $true }
            if ($WriteHistory) { $hp['WriteHistory'] = $true }
            & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') @hp
            if ($LASTEXITCODE -ne 0) {
                [void]$failures.Add('verify-os-health failed after init steps')
            }
            else {
                [void]$actions.Add('verify-os-health completed')
            }
        }
        else {
            $dp = @{}
            if ($Json) { $dp['Json'] = $true }
            if ($SkipBashSyntax) { $dp['SkipBashSyntax'] = $true }
            & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @dp
            if ($LASTEXITCODE -ne 0) {
                [void]$failures.Add('os-doctor failed after init steps')
            }
            else {
                [void]$actions.Add('os-doctor completed')
            }
        }
    }
    else {
        [void]$actions.Add('skipped validation (-NoValidation)')
    }
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'init-os-runtime' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Actions @($actions)

if ($WriteHistory -and -not $DryRun -and (Test-Path -LiteralPath (Join-Path $RepoRoot 'tools/write-validation-history.ps1'))) {
    $rec = @{
        timestamp  = (Get-Date).ToUniversalTime().ToString('o')
        event      = 'validation'
        tool       = 'init-os-runtime'
        profile    = 'n/a'
        status     = $st
        durationMs = [int]$sw.ElapsedMilliseconds
        warnings   = @($warnings)
        failures   = @($failures)
    } | ConvertTo-Json -Compress -Depth 6
    & (Join-Path $RepoRoot 'tools/write-validation-history.ps1') -Record $rec -RepoRoot $RepoRoot -Quiet
}

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "init-os-runtime: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
