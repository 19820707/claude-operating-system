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

[CmdletBinding(PositionalBinding = $false)]
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
    [switch]$SkipBashSyntax,
    [switch]$RequireBash
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

function Show-Help {
    @(
        'Claude OS Runtime v1'
        ''
        'Commands:'
        '  health                 Run repository health checks'
        '  doctor                 Diagnose runtime/environment readiness'
        '  validate [-Strict] [-SkipBashSyntax] [-RequireBash]  Release-grade validation (bash -n optional unless -RequireBash)'
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
        'help' { Show-Help }
        'health' {
            $childArgs = @{}
            if ($SkipBashSyntax) { $childArgs.SkipBashSyntax = $true }
            if ($RequireBash) { $childArgs.RequireBash = $true }
            & (Join-Path $RepoRoot 'tools/verify-os-health.ps1') @childArgs
        }
        'doctor' {
            $childArgs = @{}
            if ($Json) { $childArgs.Json = $true }
            if ($SkipBashSyntax) { $childArgs.SkipBashSyntax = $true }
            if ($RequireBash) { $childArgs.RequireBash = $true }
            & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @childArgs
        }
        'validate' {
            $childArgs = @{}
            if ($Strict) { $childArgs.Strict = $true }
            if ($SkipBashSyntax) { $childArgs.SkipBashSyntax = $true }
            if ($RequireBash) { $childArgs.RequireBash = $true }
            & (Join-Path $RepoRoot 'tools/os-validate-all.ps1') @childArgs
        }
        'route' {
            $childArgs = @{}
            if ($Query) { $childArgs.Query = $Query }
            if ($Tag) { $childArgs.Tag = $Tag }
            if ($Id) { $childArgs.Id = $Id }
            if ($Json) { $childArgs.Json = $true }
            & (Join-Path $RepoRoot 'tools/route-capability.ps1') @childArgs
        }
        'docs' {
            $childArgs = @{}
            if ($Query) { $childArgs.Query = $Query }
            if ($Tag) { $childArgs.Tag = $Tag }
            if ($Id) { $childArgs.Id = $Id }
            if ($Json) { $childArgs.Json = $true }
            & (Join-Path $RepoRoot 'tools/query-docs-index.ps1') @childArgs
        }
        'workflow' {
            $childArgs = @{}
            if ($Phase) { $childArgs.Phase = $Phase }
            if ($Json) { $childArgs.Json = $true }
            & (Join-Path $RepoRoot 'tools/workflow-status.ps1') @childArgs
        }
        'profile' {
            $childArgs = @{}
            if ($Id) { $childArgs.Id = $Id }
            if ($Json) { $childArgs.Json = $true }
            & (Join-Path $RepoRoot 'tools/runtime-profile.ps1') @childArgs
        }
        'prime' {
            $childArgs = @{}
            if ($ProjectPath) { $childArgs.ProjectPath = $ProjectPath }
            if ($Json) { $childArgs.Json = $true }
            & (Join-Path $RepoRoot 'tools/session-prime.ps1') @childArgs
        }
        'absorb' {
            if ([string]::IsNullOrWhiteSpace($Note)) { throw 'Note is required for absorb.' }
            $childArgs = @{ Note = $Note; Kind = $Kind }
            if ($ProjectPath) { $childArgs.ProjectPath = $ProjectPath }
            if ($DryRun) { $childArgs.DryRun = $true }
            & (Join-Path $RepoRoot 'tools/session-absorb.ps1') @childArgs
        }
        'digest' {
            if ([string]::IsNullOrWhiteSpace($Summary)) { throw 'Summary is required for digest.' }
            $childArgs = @{ Summary = $Summary; Outcome = $Outcome }
            if ($Validation) { $childArgs.Validation = $Validation }
            if ($Risks) { $childArgs.Risks = $Risks }
            if ($Next) { $childArgs.Next = $Next }
            if ($ProjectPath) { $childArgs.ProjectPath = $ProjectPath }
            if ($DryRun) { $childArgs.DryRun = $true }
            & (Join-Path $RepoRoot 'tools/session-digest.ps1') @childArgs
        }
        'update' {
            Require-ProjectPath
            $childArgs = @{ ProjectPath = $ProjectPath }
            if ($DryRun) { $childArgs.DryRun = $true }
            & (Join-Path $RepoRoot 'tools/os-update-project.ps1') @childArgs
        }
        'bootstrap' {
            Require-ProjectPath
            $childArgs = @{ ProjectPath = $ProjectPath }
            if ($Profile) { $childArgs.Profile = $Profile }
            if ($DryRun) { $childArgs.DryRun = $true }
            if ($SkipGitInit) { $childArgs.SkipGitInit = $true }
            & (Join-Path $RepoRoot 'init-project.ps1') @childArgs
        }
    }
} catch {
    # Invariant: no long stack traces or raw dumps in default runtime output.
    $safe = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 360
    Write-Host "ERROR: $safe"
    if ($Command -eq 'validate') {
        Write-Host ''
        Write-Host 'Isolated checks (repo root):'
        Write-Host '  pwsh ./tools/verify-os-health.ps1 -SkipBashSyntax'
        Write-Host '  pwsh ./tools/os-doctor.ps1 -Json -SkipBashSyntax'
        Write-Host '  pwsh ./tools/verify-json-contracts.ps1'
        Write-Host '  pwsh ./tools/os-validate-all.ps1 -Strict -SkipBashSyntax'
    }
    exit 1
}
