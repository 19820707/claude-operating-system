# architectural-fitness.ps1 — Architectural invariants: cycles, lib isolation, blast radius
# Fitness functions as code: structural rules enforced on every validation.
# Builds graph inline from tools/*.ps1 if script-graph.json is absent.
#   pwsh ./tools/architectural-fitness.ps1
#   pwsh ./tools/architectural-fitness.ps1 -Json
#   pwsh ./tools/architectural-fitness.ps1 -MaxBlastRadius 15 -MaxFanIn 20

param(
    [int]$MaxBlastRadius = 20,    # max transitive callers for any single file
    [int]$MaxFanIn       = 25,    # max direct callers for any single file
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw         = [System.Diagnostics.Stopwatch]::StartNew()
$warnings   = [System.Collections.Generic.List[string]]::new()
$failures   = [System.Collections.Generic.List[string]]::new()
$checks     = [System.Collections.Generic.List[object]]::new()
$violations = [System.Collections.Generic.List[object]]::new()

# ── Load or build graph ────────────────────────────────────────────────────────

$graphPath = Join-Path $RepoRoot '.claude/script-graph.json'
$adj   = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new()
$nodes = [System.Collections.Generic.HashSet[string]]::new()

if (Test-Path -LiteralPath $graphPath) {
    try {
        $g = Get-Content -LiteralPath $graphPath -Raw | ConvertFrom-Json
        foreach ($n in @($g.nodes)) { [void]$nodes.Add([string]$n.id) }
        foreach ($e in @($g.edges)) {
            $fr = [string]$e.from; $to = [string]$e.to
            if (-not $adj.ContainsKey($fr)) { $adj[$fr] = [System.Collections.Generic.HashSet[string]]::new() }
            [void]$adj[$fr].Add($to)
            [void]$nodes.Add($fr); [void]$nodes.Add($to)
        }
        [void]$checks.Add([ordered]@{ name = 'graph-load'; status = 'ok'; detail = "$($nodes.Count) nodes from script-graph.json" })
    } catch {
        [void]$warnings.Add("script-graph.json parse failed — rebuilding inline: $($_.Exception.Message)")
    }
}

if ($nodes.Count -eq 0) {
    # Inline build from source files
    $toolDir = Join-Path $RepoRoot 'tools'
    $scripts = @(Get-ChildItem -LiteralPath $toolDir -Filter '*.ps1' -File)
    $nameSet = @($scripts | ForEach-Object { $_.Name })
    foreach ($s in $scripts) { [void]$nodes.Add($s.Name); $adj[$s.Name] = [System.Collections.Generic.HashSet[string]]::new() }

    $callPatterns = @(
        [regex]"['\`"]tools[/\\]([\w][\w.-]+\.ps1)['\`"]",
        [regex]"RelativeTool\s+['\`"]tools[/\\]([\w][\w.-]+\.ps1)['\`"]"
    )
    foreach ($f in $scripts) {
        try {
            $src = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8
            foreach ($pat in $callPatterns) {
                foreach ($m in $pat.Matches($src)) {
                    $callee = $m.Groups[1].Value
                    if ($nameSet -contains $callee -and $callee -ne $f.Name) {
                        [void]$adj[$f.Name].Add($callee)
                    }
                }
            }
        } catch { }
    }
    [void]$checks.Add([ordered]@{ name = 'graph-load'; status = 'ok'; detail = "inline build: $($nodes.Count) nodes" })
}

# ── Build reverse adjacency (caller → callees → reverse: callee → callers) ───

$revAdj = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new()
foreach ($n in $nodes) { $revAdj[$n] = [System.Collections.Generic.HashSet[string]]::new() }
foreach ($kv in $adj.GetEnumerator()) {
    $caller = $kv.Key
    foreach ($callee in $kv.Value) {
        if (-not $revAdj.ContainsKey($callee)) { $revAdj[$callee] = [System.Collections.Generic.HashSet[string]]::new() }
        [void]$revAdj[$callee].Add($caller)
    }
}

# ── FITNESS 1: Cycle detection (DFS) ──────────────────────────────────────────

$cycles  = [System.Collections.Generic.List[string]]::new()
$visited = [System.Collections.Generic.HashSet[string]]::new()
$inStack = [System.Collections.Generic.HashSet[string]]::new()

function Find-Cycles {
    param([string]$Node, [System.Collections.Generic.List[string]]$Path)
    if ($inStack.Contains($Node)) {
        $cycleStart = $Path.IndexOf($Node)
        if ($cycleStart -ge 0) {
            $cycle = ($Path[$cycleStart..($Path.Count - 1)] + @($Node)) -join ' → '
            if (-not ($cycles | Where-Object { $_ -eq $cycle })) {
                [void]$script:cycles.Add($cycle)
            }
        }
        return
    }
    if ($visited.Contains($Node)) { return }
    [void]$visited.Add($Node)
    [void]$inStack.Add($Node)
    [void]$Path.Add($Node)
    $callees = if ($adj.ContainsKey($Node)) { @($adj[$Node]) } else { @() }
    foreach ($callee in $callees) { Find-Cycles -Node $callee -Path $Path }
    [void]$Path.RemoveAt($Path.Count - 1)
    [void]$inStack.Remove($Node)
}

foreach ($n in @($nodes)) { Find-Cycles -Node $n -Path ([System.Collections.Generic.List[string]]::new()) }

foreach ($c in $cycles) {
    [void]$violations.Add([ordered]@{ rule = 'no-cycles'; severity = 'HIGH'; detail = "Circular dependency: $c" })
    [void]$failures.Add("Circular dependency detected: $c")
}
[void]$checks.Add([ordered]@{ name = 'F1-cycles'; status = $(if ($cycles.Count -gt 0) {'fail'} else {'ok'}); detail = "cycles=$($cycles.Count)" })

# ── FITNESS 2: Lib isolation ───────────────────────────────────────────────────
# lib/*.ps1 must only call other lib/*.ps1 — never orchestration tools

$libViolations = 0
foreach ($n in @($nodes)) {
    if ($n -notmatch '(?i)^lib[/\\-]') { continue }
    $callees = if ($adj.ContainsKey($n)) { @($adj[$n]) } else { @() }
    foreach ($c in $callees) {
        if ($c -notmatch '(?i)^lib[/\\-]') {
            $libViolations++
            [void]$violations.Add([ordered]@{ rule = 'lib-isolation'; severity = 'MEDIUM'; detail = "lib/$n calls non-lib $c" })
            [void]$warnings.Add("lib isolation violation: $n → $c (lib must not call orchestration tools)")
        }
    }
}
[void]$checks.Add([ordered]@{ name = 'F2-lib-isolation'; status = $(if ($libViolations -gt 0) {'warn'} else {'ok'}); detail = "violations=$libViolations" })

# ── FITNESS 3: Blast radius limits ────────────────────────────────────────────
# Transitive callers via BFS

function Get-BlastRadius {
    param([string]$Node)
    $visited2 = [System.Collections.Generic.HashSet[string]]::new()
    $queue    = [System.Collections.Generic.Queue[string]]::new()
    [void]$queue.Enqueue($Node)
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        if ($visited2.Contains($cur)) { continue }
        [void]$visited2.Add($cur)
        if ($revAdj.ContainsKey($cur)) {
            foreach ($caller in $revAdj[$cur]) { [void]$queue.Enqueue($caller) }
        }
    }
    return [Math]::Max(0, $visited2.Count - 1)
}

$blastViolations = 0
foreach ($n in @($nodes)) {
    $br = Get-BlastRadius -Node $n
    $directCallers = if ($revAdj.ContainsKey($n)) { $revAdj[$n].Count } else { 0 }

    if ($br -gt $MaxBlastRadius) {
        $blastViolations++
        [void]$violations.Add([ordered]@{ rule = 'blast-radius'; severity = 'HIGH'; detail = "${n}: transitive blast=$br > limit=$MaxBlastRadius" })
        [void]$warnings.Add("blast radius exceeded: ${n} has $br transitive callers (limit $MaxBlastRadius)")
    }
    if ($directCallers -gt $MaxFanIn) {
        $blastViolations++
        [void]$violations.Add([ordered]@{ rule = 'fan-in-limit'; severity = 'MEDIUM'; detail = "${n}: direct callers=$directCallers > limit=$MaxFanIn" })
        [void]$warnings.Add("fan-in exceeded: ${n} has $directCallers direct callers (limit $MaxFanIn)")
    }
}
[void]$checks.Add([ordered]@{ name = 'F3-blast-radius'; status = $(if ($blastViolations -gt 0) {'warn'} else {'ok'}); detail = "blast-violations=$blastViolations" })

# ── FITNESS 4: Orphan detection ────────────────────────────────────────────────
# Tools with no callers AND not in entry points (os-validate*, verify-os-health, etc.)

$entryPoints = @('os-validate.ps1','os-validate-all.ps1','verify-os-health.ps1','verify-critical-systems.ps1',
                  'chaos-test.ps1','sync-manifests.ps1','autonomous-commit-gate.ps1')
$orphans = [System.Collections.Generic.List[string]]::new()

foreach ($n in @($nodes)) {
    if ($entryPoints -contains $n) { continue }
    if ($n -match '(?i)^lib[/-]') { continue }  # lib files are dot-sourced, not called
    $callers = if ($revAdj.ContainsKey($n)) { $revAdj[$n].Count } else { 0 }
    if ($callers -eq 0) { [void]$orphans.Add($n) }
}
[void]$checks.Add([ordered]@{ name = 'F4-orphans'; status = 'ok'; detail = "orphan-tools=$($orphans.Count)" })

# ── Fitness score ─────────────────────────────────────────────────────────────

$totalViolations = $cycles.Count + $libViolations + $blastViolations
$fitnessScore = [Math]::Max(0, 100 - ($cycles.Count * 20) - ($libViolations * 10) - ($blastViolations * 5))

$fitnessGrade = switch ($true) {
    ($fitnessScore -ge 95) { 'A' }
    ($fitnessScore -ge 80) { 'B' }
    ($fitnessScore -ge 65) { 'C' }
    ($fitnessScore -ge 50) { 'D' }
    default                { 'F' }
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }

$env = New-OsValidatorEnvelope -Tool 'architectural-fitness' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        fitnessScore     = $fitnessScore
        fitnessGrade     = $fitnessGrade
        nodes            = $nodes.Count
        cycles           = $cycles.Count
        libViolations    = $libViolations
        blastViolations  = $blastViolations
        orphans          = $orphans.Count
        violations       = @($violations)
        orphanList       = @($orphans | Select-Object -First 10)
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
} else {
    Write-Host "architectural-fitness | score=$fitnessScore/100 | grade=$fitnessGrade | nodes=$($nodes.Count)"
    Write-Host "  cycles=$($cycles.Count)  lib-violations=$libViolations  blast-violations=$blastViolations  orphans=$($orphans.Count)"
    foreach ($v in $violations) {
        Write-Host "  [$($v.severity)] $($v.rule): $($v.detail)"
    }
    if ($orphans.Count -gt 0 -and $orphans.Count -le 5) {
        Write-Host "  Orphaned tools (no callers): $($orphans -join ', ')"
    }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
