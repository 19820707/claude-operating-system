# verify-runtime-profiles.ps1 — Validate runtime-profiles.json
# Run from repo root or any cwd:
#   pwsh ./tools/verify-runtime-profiles.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Path = Join-Path $RepoRoot 'runtime-profiles.json'
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

if (-not (Test-Path -LiteralPath $Path)) { throw 'runtime-profiles.json not found' }
$manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

if ([int]$manifest.schemaVersion -lt 1) { Fail 'schemaVersion must be >= 1' }
if (-not $manifest.profiles) { Fail 'profiles array missing' }

$allowedCommands = @('help','health','doctor','validate','route','docs','workflow','update','bootstrap')
$seen = @{}
$defaultCount = 0

foreach ($profile in @($manifest.profiles)) {
    $id = [string]$profile.id
    if ($id -notmatch '^[a-z0-9][a-z0-9-]{0,40}$') { Fail "invalid profile id: $id" }
    if ($seen.ContainsKey($id)) { Fail "duplicate profile id: $id" }
    $seen[$id] = $true
    if ([string]::IsNullOrWhiteSpace([string]$profile.purpose)) { Fail "profile $id missing purpose" }
    if ($profile.default) { $defaultCount++ }
    $commands = @($profile.commands | ForEach-Object { [string]$_ })
    if ($commands.Count -eq 0) { Fail "profile $id has no commands" }
    foreach ($command in $commands) {
        if ($allowedCommands -notcontains $command) { Fail "profile $id has unknown command: $command" }
    }
    Write-Host "OK:  profile $id ($($commands.Count) commands)"
}

if ($defaultCount -ne 1) { Fail "expected exactly one default profile, found $defaultCount" }
if (-not $seen.ContainsKey('core')) { Fail 'missing core profile' }
if (-not $seen.ContainsKey('strict')) { Fail 'missing strict profile' }

if ($failed) { throw 'Runtime profile verification failed.' }
Write-Host ''
Write-Host 'Runtime profile checks passed.'
