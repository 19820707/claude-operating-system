# verify-workflow-manifest.ps1 — Validate workflow-manifest.json progressive delivery contract
# Run from repo root or any cwd:
#   pwsh ./tools/verify-workflow-manifest.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$workflowPath = Join-Path $RepoRoot 'workflow-manifest.json'
$capabilitiesPath = Join-Path $RepoRoot 'os-capabilities.json'
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Read-JsonFile {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Name not found at $Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "$Name is invalid JSON" }
}

function Test-SafeRelativePath {
    param([string]$Path, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail "empty path in $Field"
        return
    }
    if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        Fail "unsafe relative path '$Path' in $Field"
    }
}

Write-Host 'verify-workflow-manifest'
Write-Host "Repo: $RepoRoot"
Write-Host ''

$workflow = Read-JsonFile -Path $workflowPath -Name 'workflow-manifest.json'
$capabilities = Read-JsonFile -Path $capabilitiesPath -Name 'os-capabilities.json'

$capabilityIds = @{}
foreach ($capability in @($capabilities.capabilities)) {
    $capabilityIds[[string]$capability.id] = $true
}

if (-not $workflow.phases) { throw 'workflow-manifest.json missing phases array' }
if (@($workflow.phases).Count -lt 5) { Fail 'workflow must declare at least 5 phases' }

$seen = @{}
foreach ($phase in @($workflow.phases)) {
    $id = [string]$phase.id
    if ([string]::IsNullOrWhiteSpace($id)) { Fail 'phase has empty id'; continue }
    if ($id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { Fail "phase '$id' has invalid id format" }
    if ($seen.ContainsKey($id)) { Fail "duplicate phase id '$id'" }
    $seen[$id] = $true

    foreach ($field in @('title', 'purpose', 'gate', 'recommendedCapability')) {
        if ([string]::IsNullOrWhiteSpace([string]$phase.$field)) {
            Fail "phase '$id' missing $field"
        }
    }

    $cap = [string]$phase.recommendedCapability
    if ($cap -and -not $capabilityIds.ContainsKey($cap)) {
        Fail "phase '$id' references unknown capability '$cap'"
    }

    $artifacts = @($phase.requiredArtifacts | ForEach-Object { [string]$_ })
    if ($artifacts.Count -eq 0) { Fail "phase '$id' must declare requiredArtifacts" }
    foreach ($artifact in $artifacts) {
        if ([string]::IsNullOrWhiteSpace($artifact)) { Fail "phase '$id' contains empty required artifact" }
    }

    Write-Host "OK:  phase $id -> $cap"
}

foreach ($rule in @($workflow.globalRules | ForEach-Object { [string]$_ })) {
    if ([string]::IsNullOrWhiteSpace($rule)) { Fail 'globalRules contains empty rule' }
}

foreach ($path in @($workflow.artifactFirstPaths | ForEach-Object { [string]$_ })) {
    Test-SafeRelativePath -Path $path -Field 'artifactFirstPaths'
}

if ($failed) { throw 'Workflow manifest verification failed.' }

Write-Host ''
Write-Host "Workflow manifest checks passed ($(@($workflow.phases).Count) phases)."
exit 0
