# verify-session-memory.ps1 — Validate bounded local session memory contract
# Run from repo root or any cwd:
#   pwsh ./tools/verify-session-memory.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ManifestPath = Join-Path $RepoRoot 'session-memory-manifest.json'
$BootstrapPath = Join-Path $RepoRoot 'bootstrap-manifest.json'
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
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

Write-Host 'verify-session-memory'
Write-Host "Repo: $RepoRoot"
Write-Host ''

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw 'session-memory-manifest.json not found' }
if (-not (Test-Path -LiteralPath $BootstrapPath)) { throw 'bootstrap-manifest.json not found' }

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$bootstrap = Get-Content -LiteralPath $BootstrapPath -Raw | ConvertFrom-Json

if ([int]$manifest.schemaVersion -lt 1) { Fail 'schemaVersion must be >= 1' }
$cycle = @($manifest.cycle)
if ($cycle.Count -ne 3) { Fail "expected exactly 3 session memory cycle tools, got $($cycle.Count)" }

$expected = @('prime','absorb','digest')
$critical = @($bootstrap.projectBootstrap.criticalPaths | ForEach-Object { [string]$_ })
$seen = @{}

foreach ($item in $cycle) {
    $id = [string]$item.id
    if ($expected -notcontains $id) { Fail "unexpected cycle id: $id" }
    if ($seen.ContainsKey($id)) { Fail "duplicate cycle id: $id" }
    $seen[$id] = $true

    foreach ($field in @('tool','installedPath','mode','purpose')) {
        if ([string]::IsNullOrWhiteSpace([string]$item.$field)) { Fail "$id missing $field" }
    }

    Test-SafeRelativePath -Path ([string]$item.tool) -Field "$id.tool"
    Test-SafeRelativePath -Path ([string]$item.installedPath) -Field "$id.installedPath"

    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ([string]$item.tool)))) {
        Fail "$id tool missing: $($item.tool)"
    }
    if ($critical -notcontains [string]$item.installedPath) {
        Fail "$id installedPath missing from bootstrap criticalPaths: $($item.installedPath)"
    }

    if ($item.mode -notin @('read-only','append-only')) { Fail "$id has invalid mode: $($item.mode)" }
    if ($id -eq 'prime' -and [string]$item.mode -ne 'read-only') { Fail 'prime must be read-only' }
    if ($id -in @('absorb','digest') -and [string]$item.mode -ne 'append-only') { Fail "$id must be append-only" }

    foreach ($path in @($item.reads | ForEach-Object { [string]$_ })) { Test-SafeRelativePath -Path $path -Field "$id.reads" }
    foreach ($path in @($item.writes | ForEach-Object { [string]$_ })) {
        Test-SafeRelativePath -Path $path -Field "$id.writes"
        if (-not $path.StartsWith('.claude/')) { Fail "$id write path must stay under .claude/: $path" }
    }

    Write-Host "OK:  $id -> $($item.installedPath)"
}

foreach ($id in $expected) {
    if (-not $seen.ContainsKey($id)) { Fail "missing cycle id: $id" }
}

$rules = @($manifest.safetyRules | ForEach-Object { [string]$_ })
foreach ($term in @('No external network calls', 'No repository-wide scanning', 'No overwrite', 'Append-only')) {
    if (-not (($rules -join ' ').Contains($term))) { Fail "safetyRules missing: $term" }
}

if ($failed) { throw 'Session memory verification failed.' }
Write-Host ''
Write-Host 'Session memory checks passed.'
