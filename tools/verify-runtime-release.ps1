# verify-runtime-release.ps1 — Validate Claude OS Runtime release metadata
# Run from repo root or any cwd:
#   pwsh ./tools/verify-runtime-release.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Require-FileText {
    param([string]$RelativePath, [string[]]$Terms)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Fail "missing $RelativePath"
        return ''
    }
    $content = Get-Content -LiteralPath $path -Raw
    foreach ($term in $Terms) {
        if (-not $content.Contains($term)) { Fail "$RelativePath missing required text: $term" }
    }
    Write-Host "OK:  $RelativePath"
    return $content
}

Write-Host 'verify-runtime-release'
Write-Host "Repo: $RepoRoot"
Write-Host ''

$versionPath = Join-Path $RepoRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath)) { Fail 'missing VERSION' }
$version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { '' }
if ($version -notmatch '^\d+\.\d+\.\d+$') { Fail "VERSION must be semver, got '$version'" }

$manifestPath = Join-Path $RepoRoot 'os-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { Fail 'missing os-manifest.json' }
else {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.runtime.version -ne $version) {
        Fail "os-manifest runtime.version '$($manifest.runtime.version)' does not match VERSION '$version'"
    }
    if ([string]$manifest.runtime.level -ne 'advanced-engineering-runtime') {
        Fail 'os-manifest runtime.level must be advanced-engineering-runtime'
    }
    if (-not ([string]$manifest.validationPolicy.releaseGate).Contains('human approval required')) {
        Fail 'releaseGate must include human approval required'
    }
    Write-Host "OK:  os-manifest runtime $version"
}

Require-FileText -RelativePath 'CHANGELOG.md' -Terms @('1.0.0', 'Claude OS Runtime v1', 'human approval required') | Out-Null
Require-FileText -RelativePath 'ARCHITECTURE.md' -Terms @('Claude OS Runtime', 'os-manifest.json', 'init-project.ps1', 'Invariants') | Out-Null
Require-FileText -RelativePath 'SECURITY.md' -Terms @('human approval required', 'secrets', 'PII', 'filesystem', 'CI/CD') | Out-Null

if ($failed) { throw 'Runtime release metadata verification failed.' }

Write-Host ''
Write-Host "Runtime release metadata checks passed ($version)."
