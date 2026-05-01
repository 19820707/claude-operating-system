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
Copy-ManagedFile -From (Join-Path $RepoRoot 'workflow-manifest.json') -To (Join-Path $target '.claude/workflow-manifest.json')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/query-docs-index.ps1') -To (Join-Path $target '.claude/scripts/query-docs-index.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/route-capability.ps1') -To (Join-Path $target '.claude/scripts/route-capability.ps1')
Copy-ManagedFile -From (Join-Path $RepoRoot 'tools/workflow-status.ps1') -To (Join-Path $target '.claude/scripts/workflow-status.ps1')
Copy-ManagedDirectory -From (Join-Path $RepoRoot 'templates/checklists') -To (Join-Path $target '.claude/checklists')
Copy-ManagedDirectory -From (Join-Path $RepoRoot 'source/skills') -To (Join-Path $target '.claude/skills')

$installRecord = [pscustomobject]@{
    managedBy = 'claude-operating-system'
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    source = $RepoRoot
    artifacts = @(
        '.claude/docs-index.json',
        '.claude/os-capabilities.json',
        '.claude/workflow-manifest.json',
        '.claude/scripts/query-docs-index.ps1',
        '.claude/scripts/route-capability.ps1',
        '.claude/scripts/workflow-status.ps1',
        '.claude/checklists',
        '.claude/skills'
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
