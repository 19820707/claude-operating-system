# simulate-impact.ps1 — Change impact simulation via script dependency graph and invariants
# Given a list of files, calculates blast radius, estimates tests to run, and identifies
# invariants at risk. Output recommendation: PROCEED | REVIEW | ESCALATE_TO_OPUS
#   pwsh ./tools/simulate-impact.ps1 -Files tools/os-validate.ps1
#   pwsh ./tools/simulate-impact.ps1 -Files tools/os-runtime.ps1,tools/verify-skills.ps1 -Json

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Files,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$touchedScripts = @($Files | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Where-Object { $_ -match '\.ps1$' })
$touchedNames   = @($Files | ForEach-Object { [System.IO.Path]::GetFileName($_) })

# ── Load script graph ─────────────────────────────────────────────────────────
$directCallers    = @()
$transitiveCallers = @()
$graphPath = Join-Path $RepoRoot '.claude/script-graph.json'
if (Test-Path -LiteralPath $graphPath) {
    try {
        $graph = (Get-Content -LiteralPath $graphPath -Raw -Encoding utf8) | ConvertFrom-Json
        $revAdj = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new()
        foreach ($edge in $graph.edges) {
            if (-not $revAdj.ContainsKey($edge.to)) {
                $revAdj[$edge.to] = [System.Collections.Generic.HashSet[string]]::new()
            }
            [void]$revAdj[$edge.to].Add($edge.from)
        }
        # Direct callers
        $directSet = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($s in $touchedScripts) {
            if ($revAdj.ContainsKey($s)) {
                foreach ($c in $revAdj[$s]) { [void]$directSet.Add($c) }
            }
        }
        $directCallers = @($directSet | Sort-Object)
        # Transitive BFS
        $visited = [System.Collections.Generic.HashSet[string]]::new()
        $queue   = [System.Collections.Generic.Queue[string]]::new()
        foreach ($s in $touchedScripts) { [void]$queue.Enqueue($s) }
        while ($queue.Count -gt 0) {
            $node = $queue.Dequeue()
            if ($visited.Contains($node)) { continue }
            [void]$visited.Add($node)
            if ($revAdj.ContainsKey($node)) {
                foreach ($caller in $revAdj[$node]) { [void]$queue.Enqueue($caller) }
            }
        }
        $transitiveCallers = @($visited | Where-Object { $touchedScripts -notcontains $_ } | Sort-Object)
        [void]$checks.Add([ordered]@{ name = 'script-graph'; status = 'ok'; detail = "direct=$($directCallers.Count) transitive=$($transitiveCallers.Count)" })
    } catch {
        [void]$warnings.Add("Script graph failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'script-graph'; status = 'warn'; detail = 'load error' })
    }
} else {
    [void]$warnings.Add('script-graph.json not found — run generate-script-graph.ps1 first')
    [void]$checks.Add([ordered]@{ name = 'script-graph'; status = 'warn'; detail = 'missing' })
}

# ── Estimate affected tests ────────────────────────────────────────────────────
$affectedTests = [System.Collections.Generic.HashSet[string]]::new()
$allAffectedScripts = @($touchedScripts) + $transitiveCallers
foreach ($s in $allAffectedScripts) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($s)
    foreach ($tc in @("tests/$base.tests.ps1", "tests/$base.test.ps1", "tests/$base-tests.ps1")) {
        if (Test-Path -LiteralPath (Join-Path $RepoRoot $tc)) { [void]$affectedTests.Add($tc) }
    }
}
# Chaos test covers critical runtime scripts
$criticalScripts = @('os-runtime.ps1','os-validate.ps1','os-doctor.ps1','init-os-runtime.ps1','verify-agent-adapters.ps1')
if (@($touchedScripts | Where-Object { $criticalScripts -contains $_ }).Count -gt 0) {
    [void]$affectedTests.Add('tools/chaos-test.ps1')
}
$affectedTestsList = @($affectedTests | Sort-Object)
[void]$checks.Add([ordered]@{ name = 'test-estimate'; status = 'ok'; detail = "$($affectedTestsList.Count) test file(s)" })

# ── Identify invariants at risk ────────────────────────────────────────────────
$invAtRisk = [System.Collections.Generic.List[string]]::new()
$invDir    = Join-Path $RepoRoot 'invariants'
if (Test-Path -LiteralPath $invDir) {
    try {
        foreach ($invFile in (Get-ChildItem -LiteralPath $invDir -Filter '*.json' -File)) {
            try {
                $inv   = (Get-Content -LiteralPath $invFile.FullName -Raw -Encoding utf8) | ConvertFrom-Json
                $rules = if ($inv.PSObject.Properties.Name -contains 'rules') { @($inv.rules) } else { @($inv) }
                foreach ($rule in $rules) {
                    $ruleId  = if ($rule.PSObject.Properties.Name -contains 'id') { [string]$rule.id } else { $invFile.BaseName }
                    $targets = @()
                    if ($rule.PSObject.Properties.Name -contains 'files') { $targets += @($rule.files) }
                    if ($rule.PSObject.Properties.Name -contains 'paths') { $targets += @($rule.paths) }
                    foreach ($tgt in $targets) {
                        if ($touchedNames -contains [System.IO.Path]::GetFileName([string]$tgt)) {
                            [void]$invAtRisk.Add($ruleId); break
                        }
                    }
                }
            } catch { }
        }
        [void]$checks.Add([ordered]@{ name = 'invariants'; status = 'ok'; detail = "$($invAtRisk.Count) at risk" })
    } catch {
        [void]$warnings.Add("Invariant analysis failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'invariants'; status = 'warn'; detail = 'error' })
    }
} else {
    [void]$checks.Add([ordered]@{ name = 'invariants'; status = 'ok'; detail = 'no invariants dir' })
}

# ── Recommendation ────────────────────────────────────────────────────────────
$totalAffected  = $touchedScripts.Count + $transitiveCallers.Count
$recommendation = 'PROCEED'
$reasons        = [System.Collections.Generic.List[string]]::new()

if ($invAtRisk.Count -gt 0) {
    $recommendation = 'ESCALATE_TO_OPUS'
    [void]$reasons.Add("$($invAtRisk.Count) invariant(s) at risk")
} elseif ($totalAffected -gt 10) {
    $recommendation = 'ESCALATE_TO_OPUS'
    [void]$reasons.Add("$totalAffected files in blast radius")
} elseif ($totalAffected -ge 4 -or $affectedTestsList.Count -ge 3) {
    $recommendation = 'REVIEW'
    if ($totalAffected -ge 4)         { [void]$reasons.Add("$totalAffected files affected") }
    if ($affectedTestsList.Count -ge 3) { [void]$reasons.Add("$($affectedTestsList.Count) tests impacted") }
}
$reason = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { 'low impact' }

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'simulate-impact' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        recommendation    = $recommendation
        reason            = $reason
        filesChanged      = $Files.Count
        directCallers     = $directCallers.Count
        transitiveImpact  = $transitiveCallers.Count
        totalAffected     = $totalAffected
        testsToRun        = $affectedTestsList.Count
        invariantsAtRisk  = $invAtRisk.Count
        details           = [ordered]@{
            touched            = @($touchedScripts)
            directCallers      = $directCallers
            transitiveCallers  = $transitiveCallers
            affectedTests      = $affectedTestsList
            invariants         = @($invAtRisk)
        }
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'simulate-impact'
    Write-Host "Files    : $($Files.Count) input  ($($touchedScripts.Count) ps1 scripts)"
    Write-Host ''
    Write-Host 'IMPACT REPORT'
    Write-Host "  Direct callers    : $($directCallers.Count)"
    Write-Host "  Transitive impact : $($transitiveCallers.Count)"
    Write-Host "  Total affected    : $totalAffected"
    Write-Host "  Tests to run      : $($affectedTestsList.Count)"
    Write-Host "  Invariants at risk: $($invAtRisk.Count)"
    Write-Host ''
    Write-Host "RECOMMENDATION: $recommendation  ($reason)"
    if ($transitiveCallers.Count -gt 0) { Write-Host "  Transitive: $($transitiveCallers -join ', ')" }
    if ($affectedTestsList.Count -gt 0) { Write-Host "  Tests: $($affectedTestsList -join ', ')" }
    if ($invAtRisk.Count -gt 0)         { Write-Host "  Invariants: $(@($invAtRisk) -join ', ')" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
