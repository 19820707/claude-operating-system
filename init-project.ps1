# init-project.ps1 — Bootstrap a project with full .claude/ tree (Windows)
#   powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -ProjectPath "C:\path\to\repo" [-Profile node-ts-service|react-vite-app] [-DryRun] [-Force] [-SkipGitInit]

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$Profile = '',

    [switch]$DryRun,

    [switch]$Force,

    [string]$Source = '',

    [switch]$SkipGitInit
)

$ErrorActionPreference = 'Stop'

if (-not $Source) { $Source = $PSScriptRoot }

function Test-OsRepo {
    param([string]$Root)
    $need = @(
        (Join-Path $Root 'CLAUDE.md'),
        (Join-Path $Root 'bootstrap-manifest.json'),
        (Join-Path $Root 'templates'),
        (Join-Path $Root 'templates\commands'),
        (Join-Path $Root 'templates\scripts\preflight.sh')
    )
    foreach ($p in $need) {
        if (-not (Test-Path -LiteralPath $p)) {
            throw "OS repo invalid (missing $p). Run from claude-operating-system clone or pass -Source."
        }
    }
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
        Write-Host "  mkdir  $Path"
    }
}

function Copy-FileAlways {
    param([string]$From, [string]$To)
    $dir = Split-Path $To -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Host "  mkdir  $dir"
    }
    if ($DryRun) {
        Write-Host "  [dry]  $From -> $To"
    } else {
        Copy-Item -LiteralPath $From -Destination $To -Force
        Write-Host "  copied $From -> $To"
    }
}

function Copy-IfMissing {
    param([string]$From, [string]$To, [string]$Label)
    if (Test-Path -LiteralPath $To) {
        Write-Host "  (skip) $Label exists: $To"
        return
    }
    Copy-FileAlways -From $From -To $To
}

function Copy-ClaudeMd {
    param([string]$From, [string]$To)
    if ((Test-Path -LiteralPath $To) -and -not $Force) {
        Write-Host "  (skip) CLAUDE.md exists (use -Force): $To"
        return
    }
    if ((Test-Path -LiteralPath $To) -and $Force) {
        Write-Host '  (force) overwriting CLAUDE.md'
    }
    Copy-FileAlways -From $From -To $To
}

function Add-CrossProjectLearningSeed {
    param([string]$ProjectRoot, [string]$Source, [switch]$DryRun)
    $marker = '<!-- OS-CROSS-PROJECT-SEED -->'
    $ll = Join-Path $ProjectRoot '.claude\learning-log.md'
    $ev = Join-Path $Source 'heuristics\cross-project-evidence.json'
    if ($DryRun -or -not (Test-Path -LiteralPath $ll) -or -not (Test-Path -LiteralPath $ev)) { return }
    $raw = Get-Content -LiteralPath $ll -Raw -ErrorAction SilentlyContinue
    if ($null -eq $raw -or $raw.Contains($marker)) { return }
    try {
        $j = Get-Content -LiteralPath $ev -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        Write-Host "  (warn) could not parse cross-project-evidence.json: $_"
        return
    }
    $lines = @()
    $lines += ''
    $lines += '### Padrões herdados (cross-project)'
    $lines += ''
    $lines += $marker
    $lines += ''
    $added = $false
    foreach ($prop in $j.patterns.PSObject.Properties) {
        $name = [string]$prop.Name
        $m = $prop.Value
        $tc = 0
        if ($null -ne $m.total_confirmations) { $tc = [int]$m.total_confirmations }
        if ($tc -lt 2) { continue }
        $pr = if ($null -ne $m.promoted_to) { [string]$m.promoted_to } else { 'pending' }
        $imp = if ($null -ne $m.impact) { [string]$m.impact } else { '' }
        $lines += "- **$name** — confirmações=$tc promoted=$pr"
        if ($imp) { $lines += "  - _Impacto:_ $imp" }
        $added = $true
    }
    if (-not $added) { return }
    Add-Content -LiteralPath $ll -Value (($lines -join "`n") + "`n") -Encoding utf8
    Write-Host '  appended cross-project seed block to learning-log.md (patterns with confirmations >= 2)'
}

function Update-GitIgnore {
    param([string]$Root)
    $path = Join-Path $Root '.gitignore'
    $lines = @('.local/', '.claude/*.tmp', '.claude/os-metrics.json')
    if ($DryRun) {
        Write-Host "  [dry]  ensure .gitignore rules"
        return
    }
    $existing = @()
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
    }
    $toAdd = foreach ($l in $lines) {
        if ($existing -notcontains $l) { $l }
    }
    if ($toAdd.Count -eq 0) { return }
    $append = (($toAdd -join "`n").TrimEnd() + "`n")
    if (Test-Path -LiteralPath $path) {
        Add-Content -LiteralPath $path -Value $append -Encoding utf8
        Write-Host '  appended .gitignore rules'
    } else {
        Set-Content -LiteralPath $path -Value $append -Encoding utf8
        Write-Host '  created .gitignore'
    }
}

Test-OsRepo -Root $Source

if ($Profile -and $Profile -notin @('node-ts-service', 'react-vite-app')) {
    throw "Invalid -Profile '$Profile'. Use node-ts-service or react-vite-app."
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
$templates = Join-Path $Source 'templates'
$policiesSrc = Join-Path $Source 'policies'
$heuristicsSrc = Join-Path $Source 'heuristics'
$scriptsSrc = Join-Path $Source 'templates\scripts'
$commandsSrc = Join-Path $Source 'templates\commands'
$agentsSrc = Join-Path $Source 'templates\agents'
$criticalSrc = Join-Path $Source 'templates\critical-surfaces'
$localTpl = Join-Path $Source 'templates\local'

Write-Host ''
Write-Host 'claude-operating-system init-project'
Write-Host "Source      : $Source"
Write-Host "Project root: $ProjectRoot"
if ($Profile) { Write-Host "Profile     : $Profile" }
if ($DryRun) { Write-Host '[DRY RUN]' }
Write-Host ''

$parentDir = Split-Path $ProjectRoot -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir)) { Ensure-Dir $parentDir }
Ensure-Dir $ProjectRoot

Ensure-Dir (Join-Path $ProjectRoot '.claude')
Ensure-Dir (Join-Path $ProjectRoot '.claude\commands')
Ensure-Dir (Join-Path $ProjectRoot '.claude\agents')
Ensure-Dir (Join-Path $ProjectRoot '.claude\policies')
Ensure-Dir (Join-Path $ProjectRoot '.claude\scripts')
Ensure-Dir (Join-Path $ProjectRoot '.claude\heuristics')
Ensure-Dir (Join-Path $ProjectRoot '.local')

if (-not $SkipGitInit) {
    if ($DryRun) {
        Write-Host '  [dry]  git init'
    } else {
        Push-Location $ProjectRoot
        try {
            if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
                git init 2>&1 | Out-Host
                Write-Host '  git init'
            } else {
                Write-Host '  (skip) git init — .git exists'
            }
        } finally { Pop-Location }
    }
}

Get-ChildItem -LiteralPath $commandsSrc -Filter '*.md' -File | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot (Join-Path '.claude\commands' $_.Name))
}

Get-ChildItem -LiteralPath $agentsSrc -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot (Join-Path '.claude\agents' $_.Name))
}

Get-ChildItem -Path $policiesSrc -Filter '*.md' -File | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot (Join-Path '.claude\policies' $_.Name))
}

Get-ChildItem -LiteralPath $criticalSrc -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot (Join-Path '.claude\policies' $_.Name))
}

$scriptNames = @(
    'preflight.sh', 'session-end.sh', 'pre-compact.sh', 'post-compact.sh',
    'drift-detect.sh', 'ts-error-budget.sh', 'heuristic-ratchet.sh', 'promote-heuristics.sh', 'os-telemetry.sh',
    'risk-surface-scan.sh', 'module-complexity.sh', 'causal-trace.sh', 'session-index-build.sh', 'cross-project-inherit.sh'
)
foreach ($n in $scriptNames) {
    $sf = Join-Path $scriptsSrc $n
    if (-not (Test-Path -LiteralPath $sf)) { throw "Missing OS script: $sf" }
    Copy-FileAlways -From $sf -To (Join-Path $ProjectRoot (Join-Path '.claude\scripts' $n))
}

if (Test-Path -LiteralPath (Join-Path $heuristicsSrc 'operational.md')) {
    Copy-FileAlways -From (Join-Path $heuristicsSrc 'operational.md') -To (Join-Path $ProjectRoot '.claude\heuristics\operational.md')
}

if (Test-Path -LiteralPath (Join-Path $heuristicsSrc 'cross-project-evidence.json')) {
    Copy-IfMissing -From (Join-Path $heuristicsSrc 'cross-project-evidence.json') -To (Join-Path $ProjectRoot '.claude\heuristics\cross-project-evidence.json') -Label 'cross-project-evidence.json'
}

Copy-IfMissing -From (Join-Path $templates 'session-state.md') -To (Join-Path $ProjectRoot '.claude\session-state.md') -Label 'session-state.md'
Copy-IfMissing -From (Join-Path $templates 'learning-log.md') -To (Join-Path $ProjectRoot '.claude\learning-log.md') -Label 'learning-log.md'
Add-CrossProjectLearningSeed -ProjectRoot $ProjectRoot -Source $Source -DryRun:$DryRun
Copy-IfMissing -From (Join-Path $templates 'settings.json') -To (Join-Path $ProjectRoot '.claude\settings.json') -Label 'settings.json'

if (Test-Path -LiteralPath (Join-Path $localTpl 'ts-error-budget.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'ts-error-budget.json') -To (Join-Path $ProjectRoot '.local\ts-error-budget.json') -Label 'ts-error-budget.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'heuristic-violations.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'heuristic-violations.json') -To (Join-Path $ProjectRoot '.local\heuristic-violations.json') -Label 'heuristic-violations.json'
}

Copy-ClaudeMd -From (Join-Path $templates 'project-CLAUDE.md') -To (Join-Path $ProjectRoot 'CLAUDE.md')

if ($Profile) {
    $prof = Join-Path $Source "templates\profiles\$Profile.md"
    if (-not (Test-Path -LiteralPath $prof)) { throw "Profile file not found: $prof" }
    Copy-FileAlways -From $prof -To (Join-Path $ProjectRoot '.claude\stack-profile.md')
}

Update-GitIgnore -Root $ProjectRoot

Write-Host ''
Write-Host 'Validation (16 critical paths):'
$critical = @(
    (Join-Path $ProjectRoot 'CLAUDE.md'),
    (Join-Path $ProjectRoot '.claude\session-state.md'),
    (Join-Path $ProjectRoot '.claude\learning-log.md'),
    (Join-Path $ProjectRoot '.claude\settings.json'),
    (Join-Path $ProjectRoot '.claude\commands\session-start.md'),
    (Join-Path $ProjectRoot '.claude\heuristics\cross-project-evidence.json'),
    (Join-Path $ProjectRoot '.claude\scripts\preflight.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\session-end.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\drift-detect.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\ts-error-budget.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\heuristic-ratchet.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\promote-heuristics.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\os-telemetry.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\risk-surface-scan.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\session-index-build.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\cross-project-inherit.sh')
)
$allOk = $true
foreach ($p in $critical) {
    if (Test-Path -LiteralPath $p) {
        Write-Host "  OK   $p"
    } else {
        Write-Host "  ERR  missing $p"
        $allOk = $false
    }
}
if (-not $allOk) {
    if ($DryRun) {
        Write-Host '  (dry) validation would fail until files are written'
    } else {
        throw 'Validation failed: one or more critical paths missing.'
    }
}

Write-Host ''
Write-Host "Done. Scaffold at: $ProjectRoot"
Write-Host ''
Write-Host 'Suggested git commit:'
Write-Host ("  cd `"" + $ProjectRoot + "`"")
Write-Host '  git add CLAUDE.md .claude .local .gitignore'
Write-Host '  git commit -m "ops: bootstrap Claude operational system"'
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. bash .claude/scripts/ts-error-budget.sh   # set TS baseline (TypeScript repos)'
Write-Host '  2. Edit CLAUDE.md + .claude/session-state.md (table: Branch + HEAD)'
Write-Host '  3. Review .claude/settings.json permissions'
Write-Host ("  4. cd `"" + $ProjectRoot + "`" ; claude")
Write-Host '  5. /session-start'
Write-Host ''
