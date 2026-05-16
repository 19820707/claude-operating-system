# learn-from-failures.ps1 — Analyze CI failure history; promote recurring patterns to heuristics
# Reads gh run history, groups failures by regex pattern, promotes patterns with 2+ occurrences.
#   pwsh ./tools/learn-from-failures.ps1
#   pwsh ./tools/learn-from-failures.ps1 -Json
#   pwsh ./tools/learn-from-failures.ps1 -Limit 30 -DryRun

param(
    [switch]$Json,
    [int]$Limit = 50,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$failurePatternsPath = Join-Path $RepoRoot '.claude/failure-patterns.json'
$heuristicsPath      = Join-Path $RepoRoot '.claude/heuristics/operational.md'

# ── Pattern catalogue ─────────────────────────────────────────────────────────
$catalogue = @(
    [ordered]@{ id = 'exit-code';    regex = 'exit\s+code\s+\d+|LASTEXITCODE|missing explicit exit 0';             label = 'Exit code propagation issue' }
    [ordered]@{ id = 'manifest';     regex = 'manifest.*not found|not listed in.*manifest|exact count|mismatch';    label = 'Manifest registration missing or stale' }
    [ordered]@{ id = 'missing-file'; regex = 'Cannot find|file not found|missing.*file|not found at|does not exist'; label = 'File or path not found' }
    [ordered]@{ id = 'parse-error';  regex = 'parse error|invalid json|ConvertFrom-Json|Unexpected token';          label = 'JSON or parse error' }
    [ordered]@{ id = 'validation';   regex = 'verify-.*failed|verification failed|invariant.*failed|policy.*failed'; label = 'Validation or invariant failure' }
    [ordered]@{ id = 'git-dirty';    regex = 'dirty=True|Working tree not clean|untracked files';                   label = 'Dirty working tree in CI' }
    [ordered]@{ id = 'skills-drift'; regex = 'skills.*out of sync|skills.*drift|sync-skills';                       label = 'Generated skills out of sync' }
    [ordered]@{ id = 'permission';   regex = 'Access denied|UnauthorizedAccess|permission denied';                  label = 'Permission or access denied' }
)

$promotionThreshold = 2

# ── Load existing patterns for delta tracking ─────────────────────────────────
$existingCounts = @{}
if (Test-Path -LiteralPath $failurePatternsPath) {
    try {
        $ep = (Get-Content -LiteralPath $failurePatternsPath -Raw -Encoding utf8) | ConvertFrom-Json
        foreach ($item in @($ep.patterns)) { $existingCounts[[string]$item.id] = [int]$item.count }
    } catch { }
}

# ── Initialize counters ───────────────────────────────────────────────────────
$counts = [System.Collections.Generic.Dictionary[string, object]]::new()
foreach ($p in $catalogue) {
    $counts[$p.id] = [ordered]@{
        id       = $p.id
        label    = $p.label
        regex    = $p.regex
        count    = 0
        lastSha  = ''
        lastDate = ''
        examples = [System.Collections.Generic.List[string]]::new()
    }
}

# ── Fetch CI runs ─────────────────────────────────────────────────────────────
$runs = @()
try {
    $runsJson = & gh run list --limit $Limit --json 'conclusion,name,databaseId,headSha,createdAt' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'gh run list returned non-zero' }
    $runs = @($runsJson | ConvertFrom-Json)
    [void]$checks.Add([ordered]@{ name = 'gh-run-list'; status = 'ok'; detail = "$($runs.Count) runs fetched" })
} catch {
    [void]$warnings.Add("Failed to fetch CI runs: $($_.Exception.Message). Ensure gh CLI is authenticated.")
    [void]$checks.Add([ordered]@{ name = 'gh-run-list'; status = 'warn'; detail = 'skipped — gh unavailable' })
}

# ── Analyze each failed run ───────────────────────────────────────────────────
$failedRuns = @($runs | Where-Object { $_.conclusion -eq 'failure' })
$analyzed   = 0

foreach ($run in $failedRuns) {
    $runId = [string]$run.databaseId
    try {
        $logLines = @(& gh run view $runId --log-failed 2>$null)
        if ($LASTEXITCODE -ne 0) { continue }
        $logText = $logLines -join "`n"

        foreach ($p in $catalogue) {
            if ($logText -match $p.regex) {
                $pc = $counts[$p.id]
                $pc.count++
                if (-not $pc.lastSha) {
                    $pc.lastSha  = [string]$run.headSha
                    $pc.lastDate = [string]$run.createdAt
                }
                $exLine = ($logLines | Where-Object { $_ -match $p.regex } | Select-Object -First 1)
                if ($exLine -and $pc.examples.Count -lt 2) {
                    $ex = $exLine.Trim()
                    if ($ex.Length -gt 120) { $ex = $ex.Substring(0, 120) + '...' }
                    [void]$pc.examples.Add($ex)
                }
            }
        }
        $analyzed++
    } catch { }
}
[void]$checks.Add([ordered]@{ name = 'analyze-runs'; status = 'ok'; detail = "$analyzed of $($failedRuns.Count) failed run(s) analyzed" })

# ── Promote new patterns to heuristics ───────────────────────────────────────
$promoted = [System.Collections.Generic.List[string]]::new()

foreach ($p in $catalogue) {
    $pc       = $counts[$p.id]
    $newCount = [int]$pc.count
    $prevCount = if ($existingCounts.ContainsKey($p.id)) { $existingCounts[$p.id] } else { 0 }

    if ($newCount -ge $promotionThreshold -and $prevCount -lt $promotionThreshold) {
        $entry = @"


---

### CI-$($p.id.ToUpper()) — $($p.label)

**Evidence:** Regex pattern matched $newCount time(s) in CI failure logs (auto-promoted $(Get-Date -Format 'yyyy-MM-dd')).
**Rule:** When `$($p.regex)` appears in CI failures, use `pwsh ./tools/ci-repair.ps1` for structured repair suggestions.
**Apply:** Pattern id `$($p.id)` — check ci-repair.ps1 catalogue for matching repair action.
"@
        if (-not $DryRun -and (Test-Path -LiteralPath $heuristicsPath)) {
            $existing   = Get-Content -LiteralPath $heuristicsPath -Raw -Encoding utf8
            $newContent = $existing.TrimEnd() + $entry + "`n"
            [System.IO.File]::WriteAllText($heuristicsPath, $newContent, [System.Text.Encoding]::UTF8)
        }
        [void]$promoted.Add($p.id)
    }
}
[void]$checks.Add([ordered]@{ name = 'promote'; status = 'ok'; detail = "promoted=$($promoted.Count) dryRun=$DryRun" })

# ── Write failure-patterns.json ───────────────────────────────────────────────
$patternList = @($catalogue | ForEach-Object {
    $pc = $counts[$_.id]
    [ordered]@{
        id       = [string]$pc.id
        label    = [string]$pc.label
        count    = [int]$pc.count
        lastSha  = [string]$pc.lastSha
        lastDate = [string]$pc.lastDate
        examples = @($pc.examples)
    }
} | Sort-Object { -[int]$_.count })

if (-not $DryRun) {
    try {
        $doc = [ordered]@{
            generated    = (Get-Date).ToUniversalTime().ToString('o')
            runsAnalyzed = $analyzed
            failedRuns   = $failedRuns.Count
            patterns     = $patternList
        }
        $doc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $failurePatternsPath -Encoding utf8
        [void]$checks.Add([ordered]@{ name = 'write-patterns'; status = 'ok'; detail = $failurePatternsPath })
    } catch {
        [void]$warnings.Add("Could not write ${failurePatternsPath}: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'write-patterns'; status = 'warn'; detail = 'write error' })
    }
} else {
    [void]$checks.Add([ordered]@{ name = 'write-patterns'; status = 'ok'; detail = 'dry-run: skipped' })
}

$sw.Stop()
$active = @($patternList | Where-Object { [int]$_.count -gt 0 })
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'learn-from-failures' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        runsAnalyzed  = $analyzed
        failedRuns    = $failedRuns.Count
        patternsFound = $active.Count
        promoted      = $promoted.Count
        dryRun        = [bool]$DryRun
        patterns      = $patternList
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'learn-from-failures'
    Write-Host "Runs analyzed: $analyzed of $($failedRuns.Count) failed"
    Write-Host ''
    foreach ($pc in $patternList) {
        if ([int]$pc.count -eq 0) { continue }
        $badge = if ([int]$pc.count -ge $promotionThreshold) { '[PROMOTED]' } else { '[        ]' }
        Write-Host "  $badge $($pc.id.PadRight(14)) $($pc.count)x  $($pc.label)"
    }
    if ($promoted.Count -gt 0) {
        Write-Host ''
        Write-Host "Promoted: $($promoted -join ', ')$(if ($DryRun) { ' (dry-run)' })"
    }
    if ($active.Count -eq 0) { Write-Host '  (no patterns detected in this run)' }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
