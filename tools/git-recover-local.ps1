# git-recover-local.ps1 — Safely recover a stale local clone before pulling Runtime updates
# Usage from repo root:
#   pwsh ./tools/git-recover-local.ps1 -Mode status
#   pwsh ./tools/git-recover-local.ps1 -Mode stash
#   pwsh ./tools/git-recover-local.ps1 -Mode pull
#   pwsh ./tools/git-recover-local.ps1 -Mode validate
#
# This tool does not delete local work. Use -Mode stash before pull when the working tree is dirty.

param(
    [ValidateSet('status', 'stash', 'pull', 'validate')]
    [string]$Mode = 'status',

    [switch]$SkipBashSyntax
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Invoke-Git {
    param([string[]]$Args)
    & git @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed"
    }
}

function Assert-RepoRoot {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        throw 'This script must run from inside the claude-operating-system repository.'
    }
}

function Show-Status {
    Push-Location $RepoRoot
    try {
        Write-Host 'Repository:' $RepoRoot
        Write-Host ''
        Invoke-Git @('status', '--short', '--branch')
        Write-Host ''
        Write-Host 'Expected Runtime files after successful pull:'
        foreach ($path in @('tools/os-runtime.ps1', 'tools/os-validate-all.ps1', 'session-memory-manifest.json')) {
            if (Test-Path -LiteralPath (Join-Path $RepoRoot $path)) {
                Write-Host "  OK      $path"
            } else {
                Write-Host "  MISSING $path"
            }
        }
    } finally {
        Pop-Location
    }
}

function Save-LocalChanges {
    Push-Location $RepoRoot
    try {
        $dirty = (& git status --porcelain)
        if (-not $dirty) {
            Write-Host 'Working tree clean; no stash needed.'
            return
        }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        Invoke-Git @('stash', 'push', '-u', '-m', "claude-os-local-recovery-$stamp")
        Write-Host 'Local changes saved to git stash.'
        Write-Host 'Review later with: git stash list ; git stash show --stat stash@{0}'
    } finally {
        Pop-Location
    }
}

function Pull-Latest {
    Push-Location $RepoRoot
    try {
        $dirty = (& git status --porcelain)
        if ($dirty) {
            throw 'Working tree is dirty. Run: pwsh ./tools/git-recover-local.ps1 -Mode stash'
        }
        Invoke-Git @('pull', '--ff-only')
        Write-Host 'Repository updated with fast-forward pull.'
    } finally {
        Pop-Location
    }
}

function Validate-Runtime {
    Push-Location $RepoRoot
    try {
        foreach ($path in @('tools/os-runtime.ps1', 'tools/os-validate-all.ps1')) {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $path))) {
                throw "Required runtime file missing after pull: $path"
            }
        }
        $args = @('./tools/os-runtime.ps1', 'validate', '-Strict')
        if ($SkipBashSyntax) { $args += '-SkipBashSyntax' }
        & pwsh @args
        if ($LASTEXITCODE -ne 0) { throw 'Runtime validation failed.' }
    } finally {
        Pop-Location
    }
}

Assert-RepoRoot

switch ($Mode) {
    'status' { Show-Status }
    'stash' { Save-LocalChanges }
    'pull' { Pull-Latest }
    'validate' { Validate-Runtime }
}
exit 0
