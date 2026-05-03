# os-runtime.ps1 — Unified Claude OS Runtime dispatcher
# Examples:
#   pwsh ./tools/os-runtime.ps1 health
#   pwsh ./tools/os-runtime.ps1 validate -Strict
#   pwsh ./tools/os-runtime.ps1 critical
#   pwsh ./tools/os-runtime.ps1 route -Query "security review"
#   pwsh ./tools/os-runtime.ps1 docs -Query bootstrap
#   pwsh ./tools/os-runtime.ps1 workflow -Phase verify
#   pwsh ./tools/os-runtime.ps1 profile -Id core
#   pwsh ./tools/os-runtime.ps1 prime -ProjectPath ../my-app
#   pwsh ./tools/os-runtime.ps1 absorb -ProjectPath ../my-app -Note "Validated before editing"
#   pwsh ./tools/os-runtime.ps1 digest -ProjectPath ../my-app -Summary "Finished" -Outcome passed

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'help',
        'health',
        'doctor',
        'init',
        'validate',
        'critical',
        'route',
        'docs',
        'workflow',
        'profile',
        'prime',
        'absorb',
        'digest',
        'update',
        'bootstrap'
    )]
    [string]$Command = 'help',

    [string]$Query = '',
    [string]$Tag = '',
    [string]$Id = '',
    [string]$Phase = '',
    [string]$ProjectPath = '',
    [string]$Profile = '',
    [string]$ValidationProfile = '',
    [string]$Note = '',
    [string]$Kind = 'observation',
    [string]$Summary = '',
    [string]$Outcome = 'unknown',
    [string]$Validation = '',
    [string]$Risks = '',
    [string]$Next = '',
    [switch]$Strict,
    [switch]$Json,
    [switch]$DryRun,
    [switch]$SkipGitInit,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash,
    [switch]$WriteHistory
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

function Complete-OsChildExit {
    # Propagate non-zero exit from delegated tools (CI/agents rely on process exit, not only stderr).
    if ($LASTEXITCODE) { exit [int]$LASTEXITCODE }
}

function Show-Help {
    @(
        'Claude OS Runtime v1'
        ''
        'Commands:'
        '  health [-Strict] [-Json] [-SkipBashSyntax] [-RequireBash] [-WriteHistory]  Repository health (verify-os-health)'
        '  doctor                 Diagnose runtime/environment readiness'
        '  init                   Idempotent local runtime init (workspace context, logs/, adapter sync, doctor)'
        '  validate               Full release aggregate (os-validate-all) OR profiled checks (see below)'
        '  validate -ValidationProfile quick|standard|strict [-Json] [-WriteHistory]  Profiled orchestration (os-validate.ps1)'
        '  validate [-Strict] [-Json] [-SkipBashSyntax] [-RequireBash]  When no validation profile: os-validate-all.ps1'
        '  critical [-Json]       Verify critical-systems policy gates (token economy, no false green, scope control)'
        '  route -Query <text>    Route intent to OS capability'
        '  docs -Query <text>     Query section-first docs index'
        '  workflow [-Phase id]   Show progressive workflow gates/status'
        '  profile [-Id id]       Show local runtime profiles'
        '  prime                  Build bounded session startup context'
        '  absorb -Note <text>    Append bounded operational learning note'
        '  digest -Summary <text> Append end-of-session handoff digest'
        '  bootstrap -ProjectPath <path> [-Profile name] [-SkipGitInit]'
        '  update -ProjectPath <path> [-DryRun]'
        ''
        'Critical mutations require human approval.'
    ) | Write-Output
}

function Require-ProjectPath {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        throw 'ProjectPath is required for this command.'
    }
}

try {
    switch ($Command) {
        'help' {
            Show-Help
            break
        }
        'health' {
            $params = @{}
            if ($Strict) { $params['Strict'] = $true }
            if ($Json) { $params['Json'] = $true }
            if ($SkipBashSyntax) { $params['SkipBashSyntax'] = $true }
            if ($RequireBash) { $params['RequireBash'] = $true }
            if ($WriteHistory) { $params['WriteHistory'] = $true }
            & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') @params
            Complete-OsChildExit
            break
        }
        'init' {
            $params = @{}
            if ($Json) { $params['Json'] = $true }
            if ($SkipBashSyntax) { $params['SkipBashSyntax'] = $true }
            if ($WriteHistory) { $params['WriteHistory'] = $true }
            & (Join-Path $RepoRoot 'tools/init-os-runtime.ps1') @params
            Complete-OsChildExit
            break
        }
        'doctor' {
            $params = @{}
            if ($Json) { $params['Json'] = $true }
            if ($SkipBashSyntax) { $params['SkipBashSyntax'] = $true }
            if ($RequireBash) { $params['RequireBash'] = $true }
            & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @params
            Complete-OsChildExit
            break
        }
        'validate' {
            $vProf = $ValidationProfile
            if ([string]::IsNullOrWhiteSpace($vProf) -and ($Profile -in @('quick', 'standard', 'strict'))) {
                $vProf = $Profile
            }
            if ($vProf -in @('quick', 'standard', 'strict')) {
                $vp = @{ Profile = $vProf }
                if ($Json) { $vp['Json'] = $true }
                if ($SkipBashSyntax) { $vp['SkipBashSyntax'] = $true }
                if ($RequireBash) { $vp['RequireBash'] = $true }
                if ($WriteHistory) { $vp['WriteHistory'] = $true }
                & (Join-Path $RepoRoot 'tools/os-validate.ps1') @vp
                Complete-OsChildExit
            }
            else {
                $params = @{}
                if ($Strict) { $params['Strict'] = $true }
                if ($SkipBashSyntax) { $params['SkipBashSyntax'] = $true }
                if ($RequireBash) { $params['RequireBash'] = $true }
                if ($Json) { $params['Json'] = $true }
                if ($WriteHistory) { $params['WriteHistory'] = $true }
                & (Join-Path $RepoRoot 'tools/os-validate-all.ps1') @params
                Complete-OsChildExit
            }
            break
        }
        'critical' {
            $params = @{}
            if ($Json) { $params['Json'] = $true }
            & (Join-Path $RepoRoot 'tools/verify-critical-systems.ps1') @params
            Complete-OsChildExit
            break
        }
        'route' {
            $params = @{}
            if ($Query) { $params['Query'] = $Query }
            if ($Tag) { $params['Tag'] = $Tag }
            if ($Id) { $params['Id'] = $Id }
            if ($Json) { $params['Json'] = $true }
            & (Join-Path $RepoRoot 'tools/route-capability.ps1') @params
            Complete-OsChildExit
            break
        }
        'docs' {
            $params = @{}
            if ($Query) { $params['Query'] = $Query }
            if ($Tag) { $params['Tag'] = $Tag }
            if ($Id) { $params['Id'] = $Id }
            if ($Json) { $params['Json'] = $true }
            & (Join-Path $RepoRoot 'tools/query-docs-index.ps1') @params
            Complete-OsChildExit
            break
        }
        'workflow' {
            $params = @{}
            if ($Phase) { $params['Phase'] = $Phase }
            if ($Json) { $params['Json'] = $true }
            & (Join-Path $RepoRoot 'tools/workflow-status.ps1') @params
            Complete-OsChildExit
            break
        }
        'profile' {
            $params = @{}
            if ($Id) { $params['Id'] = $Id }
            if ($Json) { $params['Json'] = $true }
            & (Join-Path $RepoRoot 'tools/runtime-profile.ps1') @params
            Complete-OsChildExit
            break
        }
        'prime' {
            $params = @{}
            if ($ProjectPath) { $params['ProjectPath'] = $ProjectPath }
            if ($Json) { $params['Json'] = $true }
            & (Join-Path $RepoRoot 'tools/session-prime.ps1') @params
            Complete-OsChildExit
            break
        }
        'absorb' {
            if ([string]::IsNullOrWhiteSpace($Note)) { throw 'Note is required for absorb.' }
            $params = @{ Note = $Note; Kind = $Kind }
            if ($ProjectPath) { $params['ProjectPath'] = $ProjectPath }
            if ($DryRun) { $params['DryRun'] = $true }
            & (Join-Path $RepoRoot 'tools/session-absorb.ps1') @params
            Complete-OsChildExit
            break
        }
        'digest' {
            if ([string]::IsNullOrWhiteSpace($Summary)) { throw 'Summary is required for digest.' }
            $params = @{ Summary = $Summary; Outcome = $Outcome }
            if ($Validation) { $params['Validation'] = $Validation }
            if ($Risks) { $params['Risks'] = $Risks }
            if ($Next) { $params['Next'] = $Next }
            if ($ProjectPath) { $params['ProjectPath'] = $ProjectPath }
            if ($DryRun) { $params['DryRun'] = $true }
            & (Join-Path $RepoRoot 'tools/session-digest.ps1') @params
            Complete-OsChildExit
            break
        }
        'update' {
            Require-ProjectPath
            $params = @{ ProjectPath = $ProjectPath }
            if ($DryRun) { $params['DryRun'] = $true }
            & (Join-Path $RepoRoot 'tools/os-update-project.ps1') @params
            Complete-OsChildExit
            break
        }
        'bootstrap' {
            Require-ProjectPath
            $params = @{ ProjectPath = $ProjectPath }
            if ($Profile) { $params['Profile'] = $Profile }
            if ($DryRun) { $params['DryRun'] = $true }
            if ($SkipGitInit) { $params['SkipGitInit'] = $true }
            & (Join-Path $RepoRoot 'init-project.ps1') @params
            Complete-OsChildExit
            break
        }
    }
}
catch {
    # Invariant: short redacted line — no long stack traces as default output.
    $safe = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 360
    Write-Host "Claude OS runtime command failed: $safe"
    Write-Host "Command: $Command"
    Write-Host 'Suggested diagnostics:'
    Write-Host '  pwsh ./tools/verify-os-health.ps1 -SkipBashSyntax'
    Write-Host '  pwsh ./tools/os-doctor.ps1 -SkipBashSyntax'
    Write-Host '  pwsh ./tools/os-runtime.ps1 critical'
    if ($Command -eq 'validate') {
        Write-Host '  pwsh ./tools/os-validate.ps1 -Profile quick -Json'
        Write-Host '  pwsh ./tools/verify-json-contracts.ps1'
        Write-Host '  pwsh ./tools/verify-git-hygiene.ps1 -Json'
        Write-Host '  pwsh ./tools/os-validate-all.ps1 -Strict -SkipBashSyntax'
    }
    exit 1
}
