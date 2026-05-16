# os-update-project.ps1 — Refresh managed Claude OS artifacts in an existing project
# Usage:
#   pwsh ./tools/os-update-project.ps1 -ProjectPath ../my-app
#   pwsh ./tools/os-update-project.ps1 -ProjectPath ../my-app -DryRun

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

function Copy-ManagedFile {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $From)) { throw "managed source missing: $From" }
    $dir = Split-Path $To -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-StatusLine -Status 'mkdir' -Name $dir
    }
    if ($DryRun) {
        Write-StatusLine -Status 'dry' -Name "$From -> $To"
    } else {
        Copy-Item -LiteralPath $From -Destination $To -Force
        Write-StatusLine -Status 'copy' -Name "$From -> $To"
    }
}

function Copy-ManagedDirectory {
    param([string]$From, [string]$To)
    if (-not (Test-Path -LiteralPath $From)) { throw "managed source directory missing: $From" }
    Get-ChildItem -LiteralPath $From -Recurse -File | ForEach-Object {
        $rel = [System.IO.Path]::GetRelativePath($From, $_.FullName)
        if ([System.IO.Path]::IsPathRooted($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "unsafe source-relative path: $rel"
        }
        Copy-ManagedFile -From $_.FullName -To (Join-Path $To $rel)
    }
}

function Copy-ProjectOwnedIfMissing {
    param([string]$From, [string]$To, [string]$Label)
    if (Test-Path -LiteralPath $To) {
        Write-StatusLine -Status 'skip' -Name "$Label (exists — project-owned, not overwriting)"
        return
    }
    Copy-ManagedFile -From $From -To $To
}

$target = [System.IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $target)) { throw "ProjectPath not found: $target" }

Write-Host 'claude-operating-system update-project'
Write-Host "Source : $RepoRoot"
Write-Host "Project: $target"
if ($DryRun) { Write-Host '[DRY RUN]' }
Write-Host ''

# Invariant: updater refreshes managed OS artifacts only; it never overwrites project-owned state.
Copy-ManagedFile -From (Join-Path $RepoRoot 'docs-index.json') -To (Join-Path $target '.claude/docs-index.json')
Copy-ManagedFile -From (Join-Path $RepoRoot 'os-capabilities.json') -To (Join-Path $target '.claude/os-capabilities.json')
Copy-ManagedFile -From (Join-Path $RepoRoot 'capability-manifest.json') -To (Join-Path $target '.claude/capability-manifest.json')
Copy-ManagedFile -From (Join-Path $RepoRoot 'deprecation-manifest.json') -To (Join-Path $target '.claude/deprecation-manifest.json')
Copy-ManagedFile -From (Join-Path $RepoRoot 'workflow-manifest.json') -To (Join-Path $target '.claude/workflow-manifest.json')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/query-docs-index.ps1') -To (Join-Path $target '.claude/scripts/query-docs-index.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/route-capability.ps1') -To (Join-Path $target '.claude/scripts/route-capability.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/workflow-status.ps1') -To (Join-Path $target '.claude/scripts/workflow-status.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/session-prime.ps1') -To (Join-Path $target '.claude/scripts/session-prime.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/session-absorb.ps1') -To (Join-Path $target '.claude/scripts/session-absorb.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/session-digest.ps1') -To (Join-Path $target '.claude/scripts/session-digest.ps1')
Copy-ManagedDirectory -From (Join-Path $RepoRoot 'templates/checklists') -To (Join-Path $target '.claude/checklists')
Copy-ManagedDirectory -From (Join-Path $RepoRoot 'source/skills') -To (Join-Path $target '.claude/skills')
Copy-ManagedDirectory -From (Join-Path $RepoRoot 'policies') -To (Join-Path $target '.claude/policies')

# Invariant: .claudeignore is project-owned scope control. Bootstrap/update may create it, but must not overwrite local exclusions.
Copy-ProjectOwnedIfMissing -From (Join-Path $RepoRoot 'templates/claudeignore') -To (Join-Path $target '.claudeignore') -Label '.claudeignore'

$adaptersSrc = Join-Path $RepoRoot 'templates/adapters'
$agentsDest = Join-Path $target 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agentsDest)) {
    Copy-ManagedFile -From (Join-Path $adaptersSrc 'AGENTS.md') -To $agentsDest
} else {
    Write-StatusLine -Status 'skip' -Name 'AGENTS.md (exists — project-owned, not overwriting)'
}
Copy-ManagedFile -From (Join-Path $adaptersSrc 'cursor-claude-os-runtime.mdc') -To (Join-Path $target '.cursor/rules/claude-os-runtime.mdc')
Copy-ManagedFile -From (Join-Path $adaptersSrc 'agent-runtime.md') -To (Join-Path $target '.agent/runtime.md')
Copy-ManagedFile -From (Join-Path $adaptersSrc 'agent-handoff.md') -To (Join-Path $target '.agent/handoff.md')
Copy-ManagedFile -From (Join-Path $adaptersSrc 'agent-operating-contract.md') -To (Join-Path $target '.agent/operating-contract.md')
$agentsLegacyDir = Join-Path $target '.agents'
if (-not (Test-Path -LiteralPath $agentsLegacyDir)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $agentsLegacyDir -Force | Out-Null }
    Write-StatusLine -Status 'mkdir' -Name $agentsLegacyDir
}
Copy-ManagedFile -From (Join-Path $adaptersSrc 'agents-OPERATING_CONTRACT.md') -To (Join-Path $target '.agents/OPERATING_CONTRACT.md')

$installRecord = [pscustomobject]@{
    managedBy = 'claude-operating-system'
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    source = $RepoRoot
    artifacts = @(
        '.claude/docs-index.json',
        '.claude/os-capabilities.json',
        '.claude/capability-manifest.json',
        '.claude/deprecation-manifest.json',
        '.claude/workflow-manifest.json',
        '.claude/scripts/query-docs-index.ps1',
        '.claude/scripts/route-capability.ps1',
        '.claude/scripts/workflow-status.ps1',
        '.claude/scripts/session-prime.ps1',
        '.claude/scripts/session-absorb.ps1',
        '.claude/scripts/session-digest.ps1',
        '.claude/checklists',
        '.claude/skills',
        '.claude/policies',
        '.claudeignore',
        'AGENTS.md',
        '.cursor/rules/claude-os-runtime.mdc',
        '.agent/runtime.md',
        '.agent/handoff.md',
        '.agent/operating-contract.md',
        '.agents/OPERATING_CONTRACT.md'
    )
}

if (-not $DryRun) {
    $recordPath = Join-Path $target '.claude/os-install.json'
    $recordDir = Split-Path $recordPath -Parent
    if (-not (Test-Path -LiteralPath $recordDir)) { New-Item -ItemType Directory -Path $recordDir -Force | Out-Null }
    $installRecord | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath -Encoding utf8
    Write-StatusLine -Status 'write' -Name $recordPath
}

Write-Host ''
Write-Host 'Managed project artifacts refreshed.'
exit 0
