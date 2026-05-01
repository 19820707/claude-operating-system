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

function Update-GitIgnore {
    param([string]$Root)
    $path = Join-Path $Root '.gitignore'
    $lines = @('.local/', '.claude/*.tmp', '.claude/.simulation-delta-*.json', '.claude/os-metrics.json', '.claude/risk-surfaces.json', '.claude/complexity-map.json', '.claude/session-index.json', '.claude/architecture-graph.json', '.claude/subgraph-index.json', '.claude/simulation-report.json', '.claude/invariant-report.json', '.claude/invariant-lifecycle-report.json', '.claude/coordination-report.json', '.claude/epistemic-report.json', '.claude/compliance-report.json', '.claude/risk-model.json', '.claude/semantic-diff-report.json', '.claude/learning-loop-report.json', '.claude/policy-audit-report.json')
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
Ensure-Dir (Join-Path $ProjectRoot '.claude\runbooks')
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
    'agent-coordinator.sh',
    'autonomous-learning-loop.sh',
    'causal-trace.sh',
    'change-simulation.sh',
    'consolidate-runbook.sh',
    'context-allocator.sh',
    'context-topology.sh',
    'coordination-check.sh',
    'cross-project-sync.sh',
    'decision-append.sh',
    'decision-audit.sh',
    'drift-detect.sh',
    'epistemic-check.sh',
    'epistemic-state.sh',
    'heuristic-ratchet.sh',
    'invariant-engine.sh',
    'invariant-lifecycle.sh',
    'invariant-verify.sh',
    'knowledge-graph.sh',
    'living-arch-graph.sh',
    'module-complexity.sh',
    'os-telemetry.sh',
    'policy-compliance-audit.sh',
    'policy-compliance.sh',
    'post-compact.sh',
    'pre-compact.sh',
    'preflight.sh',
    'probabilistic-risk-model.sh',
    'promote-heuristics.sh',
    'risk-surface-scan.sh',
    'salience-score.sh',
    'semantic-diff-analyze.sh',
    'session-end.sh',
    'session-index.sh',
    'ts-error-budget.sh'
)
foreach ($n in $scriptNames) {
    $sf = Join-Path $scriptsSrc $n
    if (-not (Test-Path -LiteralPath $sf)) { throw "Missing OS script: $sf" }
    Copy-FileAlways -From $sf -To (Join-Path $ProjectRoot (Join-Path '.claude\scripts' $n))
}

$invBundle = Join-Path $Source 'templates\invariant-engine\dist\invariant-engine.cjs'
$invDstDir = Join-Path $ProjectRoot '.claude\invariant-engine'
if (Test-Path -LiteralPath $invBundle) {
    Ensure-Dir $invDstDir
    Copy-FileAlways -From $invBundle -To (Join-Path $invDstDir 'invariant-engine.cjs')
} else {
    Write-Host '  (warn) templates\invariant-engine\dist\invariant-engine.cjs missing — run: cd templates\invariant-engine ; npm install ; npm run build'
}

$semBundle = Join-Path $Source 'templates\invariant-engine\dist\semantic-diff.cjs'
if (Test-Path -LiteralPath $semBundle) {
    Ensure-Dir $invDstDir
    Copy-FileAlways -From $semBundle -To (Join-Path $invDstDir 'semantic-diff.cjs')
} else {
    Write-Host '  (warn) templates\invariant-engine\dist\semantic-diff.cjs missing — run npm run build in templates\invariant-engine'
}

$simDelta = Join-Path $Source 'templates\invariant-engine\dist\simulate-contract-delta.cjs'
if (Test-Path -LiteralPath $simDelta) {
    Ensure-Dir $invDstDir
    Copy-FileAlways -From $simDelta -To (Join-Path $invDstDir 'simulate-contract-delta.cjs')
} else {
    Write-Host '  (warn) templates\invariant-engine\dist\simulate-contract-delta.cjs missing'
}

$invJsonSrc = Join-Path $Source 'templates\local\invariants'
if (Test-Path -LiteralPath $invJsonSrc) {
    Ensure-Dir (Join-Path $ProjectRoot '.claude\invariants')
    Get-ChildItem -LiteralPath $invJsonSrc -Filter '*.json' -File | ForEach-Object {
        Copy-IfMissing -From $_.FullName -To (Join-Path $ProjectRoot (Join-Path '.claude\invariants' $_.Name)) -Label $_.Name
    }
}

if (-not $DryRun) {
    $syncScript = Join-Path $ProjectRoot '.claude\scripts\cross-project-sync.sh'
    $osEvidence = Join-Path $heuristicsSrc 'cross-project-evidence.json'
    if ((Test-Path -LiteralPath $syncScript) -and (Test-Path -LiteralPath $osEvidence)) {
        Write-Host '  [init] Inheriting cross-project knowledge...'
        Push-Location $ProjectRoot
        try {
            $srcUnix = ($Source -replace '\\', '/').TrimEnd('/')
            if (Get-Command bash -ErrorAction SilentlyContinue) {
                & bash '.claude/scripts/cross-project-sync.sh' '--inherit' $srcUnix 2>&1 | ForEach-Object { Write-Host "    $_" }
            } else {
                Write-Host '  (skip) bash not on PATH — run manually after install:'
                Write-Host ("    bash .claude/scripts/cross-project-sync.sh --inherit `"" + $Source + "`"")
            }
        } catch {
            Write-Host "  (warn) cross-project inherit failed: $_"
        } finally {
            Pop-Location
        }
        Write-Host '  (doc) Re-run anytime: bash .claude/scripts/cross-project-sync.sh --inherit "<path-to-claude-operating-system>"'
    }
}

if (Test-Path -LiteralPath (Join-Path $heuristicsSrc 'operational.md')) {
    Copy-FileAlways -From (Join-Path $heuristicsSrc 'operational.md') -To (Join-Path $ProjectRoot '.claude\heuristics\operational.md')
}

if (Test-Path -LiteralPath (Join-Path $heuristicsSrc 'cross-project-evidence.json')) {
    Copy-IfMissing -From (Join-Path $heuristicsSrc 'cross-project-evidence.json') -To (Join-Path $ProjectRoot '.claude\heuristics\cross-project-evidence.json') -Label 'cross-project-evidence.json'
}

Copy-IfMissing -From (Join-Path $templates 'session-state.md') -To (Join-Path $ProjectRoot '.claude\session-state.md') -Label 'session-state.md'
Copy-IfMissing -From (Join-Path $templates 'learning-log.md') -To (Join-Path $ProjectRoot '.claude\learning-log.md') -Label 'learning-log.md'
Copy-IfMissing -From (Join-Path $templates 'settings.json') -To (Join-Path $ProjectRoot '.claude\settings.json') -Label 'settings.json'

if (Test-Path -LiteralPath (Join-Path $localTpl 'ts-error-budget.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'ts-error-budget.json') -To (Join-Path $ProjectRoot '.local\ts-error-budget.json') -Label 'ts-error-budget.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'heuristic-violations.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'heuristic-violations.json') -To (Join-Path $ProjectRoot '.local\heuristic-violations.json') -Label 'heuristic-violations.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'architecture-boundaries.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'architecture-boundaries.json') -To (Join-Path $ProjectRoot '.claude\architecture-boundaries.json') -Label 'architecture-boundaries.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'learning-loop-state.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'learning-loop-state.json') -To (Join-Path $ProjectRoot '.claude\learning-loop-state.json') -Label 'learning-loop-state.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'knowledge-graph.seed.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'knowledge-graph.seed.json') -To (Join-Path $ProjectRoot '.claude\knowledge-graph.json') -Label 'knowledge-graph.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'decision-log.schema.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'decision-log.schema.json') -To (Join-Path $ProjectRoot '.claude\decision-log.schema.json') -Label 'decision-log.schema.json'
}
$coreInv = Join-Path $Source 'templates\invariants\core.json'
if (Test-Path -LiteralPath $coreInv) {
    Copy-IfMissing -From $coreInv -To (Join-Path $ProjectRoot '.claude\invariants.json') -Label 'invariants.json (core pack)'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'agent-state.seed.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'agent-state.seed.json') -To (Join-Path $ProjectRoot '.claude\agent-state.json') -Label 'agent-state.json'
}
if (Test-Path -LiteralPath (Join-Path $localTpl 'epistemic-state.seed.json')) {
    Copy-IfMissing -From (Join-Path $localTpl 'epistemic-state.seed.json') -To (Join-Path $ProjectRoot '.claude\epistemic-state.json') -Label 'epistemic-state.json'
}

$decisionLog = Join-Path $ProjectRoot '.claude\decision-log.jsonl'
if (-not $DryRun -and -not (Test-Path -LiteralPath $decisionLog)) {
    New-Item -ItemType File -Path $decisionLog -Force | Out-Null
    Write-Host '  touch    decision-log.jsonl'
}

Copy-ClaudeMd -From (Join-Path $templates 'project-CLAUDE.md') -To (Join-Path $ProjectRoot 'CLAUDE.md')

if ($Profile) {
    $prof = Join-Path $Source "templates\profiles\$Profile.md"
    if (-not (Test-Path -LiteralPath $prof)) { throw "Profile file not found: $prof" }
    Copy-FileAlways -From $prof -To (Join-Path $ProjectRoot '.claude\stack-profile.md')
}

Update-GitIgnore -Root $ProjectRoot

Write-Host ''
Write-Host 'Validation (40 critical paths):'
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
    (Join-Path $ProjectRoot '.claude\scripts\session-index.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\cross-project-sync.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\causal-trace.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\module-complexity.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\living-arch-graph.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\invariant-verify.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\probabilistic-risk-model.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\semantic-diff-analyze.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\autonomous-learning-loop.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\decision-append.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\policy-compliance-audit.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\context-topology.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\invariant-lifecycle.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\coordination-check.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\epistemic-check.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\decision-audit.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\policy-compliance.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\knowledge-graph.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\context-allocator.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\invariant-engine.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\agent-coordinator.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\epistemic-state.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\salience-score.sh'),
    (Join-Path $ProjectRoot '.claude\scripts\change-simulation.sh'),
    (Join-Path $ProjectRoot '.claude\invariant-engine\simulate-contract-delta.cjs'),
    (Join-Path $ProjectRoot '.claude\scripts\consolidate-runbook.sh')
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
Write-Host '  6. Cross-project (optional): bash .claude/scripts/cross-project-sync.sh --inherit "<path-to-claude-operating-system-clone>"'
Write-Host '  7. Invariants (optional): INVARIANT_VERIFY=1 on SessionStart, or: bash .claude/scripts/invariant-verify.sh'
Write-Host '  8. Invariant lifecycle (optional): INVARIANT_LIFECYCLE=1 or: bash .claude/scripts/invariant-lifecycle.sh [--for path] [--apply]'
Write-Host '  9. Multi-agent coordination (optional): COORDINATION_CHECK=1 or: bash .claude/scripts/coordination-check.sh [--paths a,b]'
Write-Host ' 10. Epistemic state (optional): EPISTEMIC_CHECK=1 or: bash .claude/scripts/epistemic-check.sh [--gate --depends k1,k2] [--score-decision D-...] [--decision-debt]'
Write-Host ''
