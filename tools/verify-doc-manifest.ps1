# verify-doc-manifest.ps1 — Fail if INDEX.md summary drifts from bootstrap-manifest.json
# Run from repo root or any cwd (uses script location):
#   pwsh ./tools/verify-doc-manifest.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $RepoRoot "bootstrap-manifest.json"
$indexPath = Join-Path $RepoRoot "INDEX.md"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "bootstrap-manifest.json not found at $manifestPath"
}
if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "INDEX.md not found at $indexPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$index = Get-Content -LiteralPath $indexPath -Raw
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Require-Text {
    param(
        [string]$Text,
        [string]$Why
    )
    if (-not $index.Contains($Text)) {
        Fail "$Why — missing literal: $Text"
    } else {
        Write-Host "OK:  $Why"
    }
}

function Get-ExactCount {
    param([string]$RelativePath)
    $rule = $manifest.repoIntegrity.$RelativePath
    if (-not $rule -or -not ($rule.PSObject.Properties.Name -contains 'exact')) {
        throw "Missing exact repoIntegrity count for $RelativePath"
    }
    return [int]$rule.exact
}

Write-Host "verify-doc-manifest"
Write-Host "Repo    : $RepoRoot"
Write-Host "Manifest: $manifestPath"
Write-Host "Index   : $indexPath"
Write-Host ""

$commands = Get-ExactCount -RelativePath 'templates/commands'
$scripts = Get-ExactCount -RelativePath 'templates/scripts'
$agents = Get-ExactCount -RelativePath 'templates/agents'
$profiles = Get-ExactCount -RelativePath 'templates/profiles'
$criticalSurfaces = Get-ExactCount -RelativePath 'templates/critical-surfaces'
$bundles = Get-ExactCount -RelativePath 'templates/invariant-engine/dist'

# Invariant: documentation summaries must quote manifest-backed counts, not stale hardcoded history.
Require-Text "Commands to copy into ``.claude/commands/`` of each project. Canonical count: **$commands/$commands** from ``bootstrap-manifest.json``." "commands section count"
Require-Text "Session lifecycle hooks. Copy to ``.claude/scripts/`` — **must remain LF-only**. Canonical count: **$scripts/$scripts** from ``bootstrap-manifest.json``; ``init-project.ps1`` consumes that manifest list directly." "scripts section count"
Require-Text "| templates/commands/ | $commands/$commands — manifest verified |" "system state commands count"
Require-Text "| templates/scripts/ | $scripts/$scripts — manifest verified; CI runs ``bash -n`` |" "system state scripts count"
Require-Text "| templates/invariant-engine/dist/ | $bundles/$bundles — invariant-engine, semantic-diff, simulate-contract-delta |" "system state invariant bundle count"
Require-Text "| templates/profiles/ | $profiles/$profiles — node-ts-service, react-vite-app |" "system state profiles count"
Require-Text "| templates/agents/ |" "agents section exists"
Require-Text "| templates/critical-surfaces/ | $criticalSurfaces/9 — auth, migrations, billing, deploy, pii |" "system state critical-surface count"
Require-Text "manifest-driven validation" "init-project description"
Require-Text "tools/verify-doc-manifest.ps1" "doc verifier listed"

foreach ($script in @($manifest.projectBootstrap.scripts)) {
    Require-Text ([string]$script) "manifest script documented or referenced: $script"
}

if ($failed) {
    throw "Documentation manifest verification failed. Update INDEX.md or bootstrap-manifest.json."
}

Write-Host ""
Write-Host "INDEX.md is aligned with bootstrap-manifest.json."
