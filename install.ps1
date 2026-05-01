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
if ($DryRun) { Write-Host "[DRY RUN - no files written]" }
Write-Host ""

# 1. Global CLAUDE.md
Copy-Safe "$Source\CLAUDE.md" "$Target\CLAUDE.md"

# 2. Global policies (all *.md in policies/)
Get-ChildItem -Path "$Source\policies" -Filter "*.md" -File | ForEach-Object {
    Copy-Safe $_.FullName "$Target\policies\$($_.Name)"
}

# 3. Global prompts (all *.md in prompts/)
Get-ChildItem -Path "$Source\prompts" -Filter "*.md" -File | ForEach-Object {
    Copy-Safe $_.FullName "$Target\prompts\$($_.Name)"
}

# 4. Global heuristics (all *.md in heuristics/)
if (Test-Path "$Source\heuristics") {
    Get-ChildItem -Path "$Source\heuristics" -Filter "*.md" -File | ForEach-Object {
        Copy-Safe $_.FullName "$Target\heuristics\$($_.Name)"
    }
}

# 5. Install provenance (audit / support — no secrets)
if (-not $DryRun) {
    $meta = [ordered]@{
        schemaVersion = 1
        installedAt   = (Get-Date).ToString("o")
        sourcePath    = (Resolve-Path -LiteralPath $Source).Path
        targetPath    = (Resolve-Path -LiteralPath $Target).Path
        sourceSha     = $null
    }
    $gitHead = Join-Path $Source ".git\HEAD"
    if (Test-Path -LiteralPath $gitHead) {
        try {
            Push-Location $Source
            $sha = (& git rev-parse HEAD 2>$null)
            if ($LASTEXITCODE -eq 0 -and $sha) { $meta.sourceSha = $sha.Trim() }
        } catch { }
        finally { Pop-Location }
    }
    $installRecord = Join-Path $Target "os-install.json"
    ($meta | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $installRecord -Encoding utf8
    Write-Host "  wrote  $installRecord"
}

Write-Host ""
Write-Host "Done. ~/.claude/ is ready."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Install Claude Code: https://claude.ai/download"
Write-Host "  2. New Windows project: .\init-project.ps1 -ProjectPath `"$env:USERPROFILE\claude\<project>`" [-Profile node-ts-service|react-vite-app]"
Write-Host "  3. Clone each project repo (contains .claude/ with session-state, learning-log, commands, agents)"
Write-Host "  4. Open Claude Code in the project directory"
Write-Host "  5. Type /session-start to recover operational context"
