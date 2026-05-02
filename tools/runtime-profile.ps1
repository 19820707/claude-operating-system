# runtime-profile.ps1 — Inspect Claude OS runtime profiles
# Examples:
#   pwsh ./tools/runtime-profile.ps1
#   pwsh ./tools/runtime-profile.ps1 -Id core
#   pwsh ./tools/runtime-profile.ps1 -Id strict -Json

param(
    [string]$Id = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$profilePath = Join-Path $RepoRoot 'runtime-profiles.json'

if (-not (Test-Path -LiteralPath $profilePath)) {
    throw 'runtime-profiles.json not found'
}

$manifest = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$profiles = @($manifest.profiles)
if ($Id) {
    $profiles = @($profiles | Where-Object { [string]$_.id -eq $Id })
    if ($profiles.Count -eq 0) { throw "Unknown runtime profile: $Id" }
}

$result = [pscustomobject]@{
    schemaVersion = $manifest.schemaVersion
    count = $profiles.Count
    profiles = $profiles
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}

Write-Host 'Claude OS runtime profiles'
Write-Host ''
foreach ($prof in $profiles) {
    Write-Host "[$($prof.id)] $($prof.purpose)"
    Write-Host "  commands: $(@($prof.commands) -join ', ')"
    if ($prof.default) { Write-Host '  default : true' }
    Write-Host ''
}
