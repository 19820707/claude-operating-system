# session-absorb.ps1 — Append a bounded operational note to the project learning log
# Inspired by absorb: capture useful learning during work without requiring a database.
# Run from a bootstrapped project root:
#   pwsh .claude/scripts/session-absorb.ps1 -Note "Validated route before editing"

param(
    [Parameter(Mandatory = $true)]
    [string]$Note,

    [string]$ProjectPath = '.',
    [string]$Kind = 'observation',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath($ProjectPath)
$LogPath = Join-Path $Root '.claude/learning-log.md'

if (-not (Test-Path -LiteralPath (Join-Path $Root '.claude'))) {
    throw '.claude directory not found. Run from a bootstrapped project or pass -ProjectPath.'
}
if ([string]::IsNullOrWhiteSpace($Note)) { throw 'Note cannot be empty.' }
if ($Note.Length -gt 1000) { throw 'Note is too long; keep absorb notes under 1000 characters.' }
if ($Kind -notmatch '^[a-z0-9][a-z0-9-]{0,40}$') { throw 'Kind must be a short slug.' }

$stamp = (Get-Date).ToUniversalTime().ToString('o')
$entry = "`n## Absorb — $stamp`n`n- kind: $Kind`n- note: $($Note.Trim())`n"

# Invariant: absorb appends bounded human-readable notes only; it never rewrites prior learning.
if ($DryRun) {
    Write-Host $entry
    exit 0
}

$dir = Split-Path $LogPath -Parent
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $LogPath)) { New-Item -ItemType File -Path $LogPath -Force | Out-Null }
Add-Content -LiteralPath $LogPath -Value $entry -Encoding utf8
Write-Host 'Absorbed note into .claude/learning-log.md'
