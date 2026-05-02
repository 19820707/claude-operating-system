# os-runtime.ps1 — Unified Claude OS Runtime dispatcher
# Examples:
#   pwsh ./tools/os-runtime.ps1 health
#   pwsh ./tools/os-runtime.ps1 validate -Strict
#   pwsh ./tools/os-runtime.ps1 route -Query "security review"
#   pwsh ./tools/os-runtime.ps1 docs -Query bootstrap
#   pwsh ./tools/os-runtime.ps1 workflow -Phase verify
#   pwsh ./tools/os-runtime.ps1 profile -Id core
#   pwsh ./tools/os-runtime.ps1 prime -ProjectPath ../my-app
#   pwsh ./tools/os-runtime.ps1 absorb -ProjectPath ../my-app -Note "Validated before editing"
#   pwsh ./tools/os-runtime.ps1 digest -ProjectPath ../my-app -Summary "Finished" -Outcome passed

param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'health', 'doctor', 'validate', 'route', 'docs', 'workflow', 'profile', 'prime', 'absorb', 'digest', 'update', 'bootstrap')]
    [string]$Command = 'help',

    [string]$Query = '',
    [string]$Tag = '',
    [string]$Id = '',
    [string]$Phase = '',
    [string]$ProjectPath = '',
    [string]$Profile = '',
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
    [switch]$SkipBashSyntax
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

function Show-Help {
    Write-Host 'Claude OS Runtime v1'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  health                 Run repository health checks'
    Write-Host '  doctor                 Diagnose runtime/environment readiness'
    Write-Host '  validate [-Strict]     Run release-grade aggregate validation'
    Write-Host '  route -Query <text>    Route intent to OS capability'
    Write-Host '  docs -Query <text>     Query section-first docs index'
    Write-Host '  workflow [-Phase id]   Show progressive workflow gates/status'
    Write-Host '  profile [-Id id]       Show local runtime profiles'
    Write-Host '  prime                  Build bounded session startup context'
    Write-Host '  absorb -Note <text>    Append bounded operational learning note'
    Write-Host '  digest -Summary <text> Append end-of-session handoff digest'
    Write-Host '  bootstrap -ProjectPath <path> [-Profile name] [-SkipGitInit]'
    Write-Host '  update -ProjectPath <path> [-DryRun]'
    Write-Host ''
    Write-Host 'Critical mutations require human approval.'
}

function Require-ProjectPath {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        throw 'ProjectPath is required for this command.'
    }
}

try {
    switch ($Command) {
        'help' { Show-Help }
        'health' {
            $args = @()
            if ($SkipBashSyntax) { $args += '-SkipBashSyntax' }
            & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') @args
        }
        'doctor' {
            $args = @()
            if ($Json) { $args += '-Json' }
            & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @args
        }
        'validate' {
            $args = @()
            if ($Strict) { $args += '-Strict' }
            if ($SkipBashSyntax) { $args += '-SkipBashSyntax' }
            & (Join-Path $RepoRoot 'tools/os-validate-all.ps1') @args
        }
        'route' {
            $args = @()
            if ($Query) { $args += @('-Query', $Query) }
            if ($Tag) { $args += @('-Tag', $Tag) }
            if ($Id) { $args += @('-Id', $Id) }
            if ($Json) { $args += '-Json' }
            & (Join-Path $RepoRoot 'tools/route-capability.ps1') @args
        }
        'docs' {
            $args = @()
            if ($Query) { $args += @('-Query', $Query) }
            if ($Tag) { $args += @('-Tag', $Tag) }
            if ($Id) { $args += @('-Id', $Id) }
            if ($Json) { $args += '-Json' }
            & (Join-Path $RepoRoot 'tools/query-docs-index.ps1') @args
        }
        'workflow' {
            $args = @()
            if ($Phase) { $args += @('-Phase', $Phase) }
            if ($Json) { $args += '-Json' }
            & (Join-Path $RepoRoot 'tools/workflow-status.ps1') @args
        }
        'profile' {
            $args = @()
            if ($Id) { $args += @('-Id', $Id) }
            if ($Json) { $args += '-Json' }
            & (Join-Path $RepoRoot 'tools/runtime-profile.ps1') @args
        }
        'prime' {
            $args = @()
            if ($ProjectPath) { $args += @('-ProjectPath', $ProjectPath) }
            if ($Json) { $args += '-Json' }
            & (Join-Path $RepoRoot 'tools/session-prime.ps1') @args
        }
        'absorb' {
            if ([string]::IsNullOrWhiteSpace($Note)) { throw 'Note is required for absorb.' }
            $args = @('-Note', $Note, '-Kind', $Kind)
            if ($ProjectPath) { $args += @('-ProjectPath', $ProjectPath) }
            if ($DryRun) { $args += '-DryRun' }
            & (Join-Path $RepoRoot 'tools/session-absorb.ps1') @args
        }
        'digest' {
            if ([string]::IsNullOrWhiteSpace($Summary)) { throw 'Summary is required for digest.' }
            $args = @('-Summary', $Summary, '-Outcome', $Outcome)
            if ($Validation) { $args += @('-Validation', $Validation) }
            if ($Risks) { $args += @('-Risks', $Risks) }
            if ($Next) { $args += @('-Next', $Next) }
            if ($ProjectPath) { $args += @('-ProjectPath', $ProjectPath) }
            if ($DryRun) { $args += '-DryRun' }
            & (Join-Path $RepoRoot 'tools/session-digest.ps1') @args
        }
        'update' {
            Require-ProjectPath
            $args = @('-ProjectPath', $ProjectPath)
            if ($DryRun) { $args += '-DryRun' }
            & (Join-Path $RepoRoot 'tools/os-update-project.ps1') @args
        }
        'bootstrap' {
            Require-ProjectPath
            $args = @('-ProjectPath', $ProjectPath)
            if ($Profile) { $args += @('-Profile', $Profile) }
            if ($DryRun) { $args += '-DryRun' }
            if ($SkipGitInit) { $args += '-SkipGitInit' }
            & (Join-Path $RepoRoot 'init-project.ps1') @args
        }
    }
} catch {
    throw (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 240)
}
