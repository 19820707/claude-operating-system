# install.ps1 — Bootstrap ~/.claude/ from claude-operating-system
# Run after cloning this repo on a new machine:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Safe to re-run: copies only, never deletes existing files.

param(
    [string]$Target = "$env:USERPROFILE\.claude",
    [switch]$DryRun
)

$Source = $PSScriptRoot
$ErrorActionPreference = "Stop"

function Copy-Safe {
    param([string]$From, [string]$To)
    $dir = Split-Path $To -Parent
    if (-not (Test-Path $dir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Host "  mkdir  $dir"
    }
    if ($DryRun) {
        Write-Host "  [dry]  $From -> $To"
    } else {
        Copy-Item $From $To -Force
        Write-Host "  copied $From -> $To"
    }
}

Write-Host ""
Write-Host "claude-operating-system install"
Write-Host "Source : $Source"
Write-Host "Target : $Target"
if ($DryRun) { Write-Host "[DRY RUN — no files written]" }
Write-Host ""

# 1. Global CLAUDE.md
Copy-Safe "$Source\CLAUDE.md" "$Target\CLAUDE.md"

# 2. Global policies
foreach ($f in @("model-selection.md","operating-modes.md","engineering-governance.md","production-safety.md")) {
    Copy-Safe "$Source\policies\$f" "$Target\policies\$f"
}

# 3. Global prompts
Copy-Safe "$Source\prompts\session-start.md" "$Target\prompts\session-start.md"

Write-Host ""
Write-Host "Done. ~/.claude/ is ready."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Install Claude Code: https://claude.ai/download"
Write-Host "  2. Clone each project repo (contains .claude/ with session-state, learning-log, commands, agents)"
Write-Host "  3. Open Claude Code in the project directory"
Write-Host "  4. Type /session-start to recover operational context"
