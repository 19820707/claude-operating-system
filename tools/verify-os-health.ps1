# verify-os-health.ps1 — Aggregate Claude OS health verifier
# Run from repo root or any cwd (uses script location):
#   pwsh ./tools/verify-os-health.ps1
# Optional:
#   pwsh ./tools/verify-os-health.ps1 -SkipBootstrapSmoke -SkipBashSyntax

param(
    [switch]$SkipBootstrapSmoke,
    [switch]$SkipBashSyntax
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Failures = @()
$Results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [int]$LatencyMs,
        [string]$Note = ''
    )
    $script:Results += [pscustomobject]@{
        name = $Name
        status = $Status
        latency_ms = $LatencyMs
        note = $Note
    }
}

function Invoke-HealthStep {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Script
        $sw.Stop()
        Add-Result -Name $Name -Status 'ok' -LatencyMs ([int]$sw.ElapsedMilliseconds)
    } catch {
        $sw.Stop()
        # Invariant: health output is concise; no raw stack traces or dumped JSON.
        $msg = $_.Exception.Message
        if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) + '...' }
        Add-Result -Name $Name -Status 'fail' -LatencyMs ([int]$sw.ElapsedMilliseconds) -Note $msg
        $script:Failures += $Name
    }
}

function Test-PowerShellSyntax {
    param([string[]]$Files)
    foreach ($file in $Files) {
        if (-not (Test-Path -LiteralPath $file)) {
            throw "PowerShell file missing: $file"
        }
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $first = $errors[0]
            throw "Parse error in $(Split-Path $file -Leaf): $($first.Message)"
        }
    }
}

function Test-BashSyntax {
    if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
        throw 'bash not found on PATH'
    }
    Push-Location $RepoRoot
    try {
        & bash -n 'install.sh'
        if ($LASTEXITCODE -ne 0) { throw 'bash -n install.sh failed' }
        $scripts = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'templates/scripts') -Filter '*.sh' -File | Sort-Object Name)
        foreach ($script in $scripts) {
            & bash -n $script.FullName
            if ($LASTEXITCODE -ne 0) { throw "bash -n failed: $($script.Name)" }
        }
    } finally {
        Pop-Location
    }
}

function Test-BootstrapSmoke {
    $target = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-os-health-' + [System.Guid]::NewGuid().ToString('N'))
    try {
        & (Join-Path $RepoRoot 'init-project.ps1') -ProjectPath $target -SkipGitInit
        if ($LASTEXITCODE -ne 0) { throw 'init-project.ps1 returned a non-zero exit code' }
        $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'bootstrap-manifest.json') -Raw | ConvertFrom-Json
        $missing = @()
        foreach ($rel in @($manifest.projectBootstrap.criticalPaths)) {
            $path = Join-Path $target ([string]$rel)
            if (-not (Test-Path -LiteralPath $path)) { $missing += [string]$rel }
        }
        if ($missing.Count -gt 0) {
            throw "bootstrap smoke missing $($missing.Count) critical path(s)"
        }
    } finally {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-DocsIndexQuery {
    $raw = & (Join-Path $RepoRoot 'tools/query-docs-index.ps1') -Query health -Limit 1 -Json
    if ($LASTEXITCODE -ne 0) { throw 'query-docs-index.ps1 returned non-zero exit code' }
    $result = ($raw | Out-String) | ConvertFrom-Json
    if ([int]$result.count -lt 1) { throw 'query-docs-index.ps1 returned no health result' }
}

Write-Host 'claude-operating-system health'
Write-Host "Repo: $RepoRoot"
Write-Host ''

Invoke-HealthStep -Name 'manifest' -Script { & (Join-Path $RepoRoot 'tools/verify-bootstrap-manifest.ps1') }
Invoke-HealthStep -Name 'skills' -Script { & (Join-Path $RepoRoot 'tools/verify-skills.ps1') }
Invoke-HealthStep -Name 'docs' -Script { & (Join-Path $RepoRoot 'tools/verify-doc-manifest.ps1') }
Invoke-HealthStep -Name 'docs-index' -Script { & (Join-Path $RepoRoot 'tools/verify-docs-index.ps1') }
Invoke-HealthStep -Name 'docs-index-query' -Script { Test-DocsIndexQuery }
Invoke-HealthStep -Name 'powershell-syntax' -Script {
    Test-PowerShellSyntax -Files @(
        (Join-Path $RepoRoot 'install.ps1'),
        (Join-Path $RepoRoot 'init-project.ps1'),
        (Join-Path $RepoRoot 'tools/verify-bootstrap-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/verify-doc-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/verify-docs-index.ps1'),
        (Join-Path $RepoRoot 'tools/query-docs-index.ps1'),
        (Join-Path $RepoRoot 'tools/verify-skills.ps1'),
        (Join-Path $RepoRoot 'tools/verify-os-health.ps1')
    )
}

if (-not $SkipBootstrapSmoke) {
    Invoke-HealthStep -Name 'bootstrap-real-smoke' -Script { Test-BootstrapSmoke }
} else {
    Add-Result -Name 'bootstrap-real-smoke' -Status 'skip' -LatencyMs 0 -Note 'skipped by flag'
}

if (-not $SkipBashSyntax) {
    Invoke-HealthStep -Name 'bash-syntax' -Script { Test-BashSyntax }
} else {
    Add-Result -Name 'bash-syntax' -Status 'skip' -LatencyMs 0 -Note 'skipped by flag'
}

Write-Host ''
Write-Host 'Summary:'
foreach ($r in $Results) {
    $line = "  $($r.status.ToUpper().PadRight(4)) $($r.name) ($($r.latency_ms) ms)"
    if ($r.note) { $line += " — $($r.note)" }
    Write-Host $line
}

$totalMs = ($Results | Measure-Object -Property latency_ms -Sum).Sum
Write-Host ''
Write-Host "Health checks: $($Results.Count), failures: $($Failures.Count), total: $totalMs ms"

if ($Failures.Count -gt 0) {
    throw "Claude OS health failed: $($Failures -join ', ')"
}

Write-Host 'Claude OS health passed.'
