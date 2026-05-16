# change-velocity-gate.ps1 — Circuit breaker for change rate and failure cascades
# Detects: fix-of-fix chains, high-churn files, burst commit patterns, elevated failure rate.
# Financial-grade: slow down when signals indicate instability before it compounds.
#   pwsh ./tools/change-velocity-gate.ps1
#   pwsh ./tools/change-velocity-gate.ps1 -Window 7 -Json
# Override: set CLAUDE_OS_FORCE_VELOCITY=1

param(
    [int]$Window         = 14,     # days of git history to analyse
    [double]$WarnScore   = 0.55,
    [double]$BlockScore  = 0.80,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw       = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()
$signals  = [System.Collections.Generic.List[object]]::new()

$forceVelocity = ($env:CLAUDE_OS_FORCE_VELOCITY -eq '1')

# ── SIGNAL 1: Fix-of-fix chain detection ─────────────────────────────────────
# Pattern: fix commit followed within 48h by another fix commit on same file = instability signal

$fixOfFixScore = 0.0
try {
    $logLines = @(& git -C $RepoRoot log --format='%H|%cd|%s' --date=iso `
        --since="${Window} days ago" 2>$null | Where-Object { $_ -match '\S' })

    $commits = [System.Collections.Generic.List[object]]::new()
    foreach ($l in $logLines) {
        $p = $l -split '\|', 3
        if ($p.Count -lt 3) { continue }
        [void]$commits.Add([ordered]@{
            hash    = $p[0].Trim()
            dateStr = $p[1].Trim()
            subject = $p[2].Trim()
            isFix   = ($p[2] -match '(?i)\bfix|revert|hotfix\b')
        })
    }

    # Get files for fix commits
    $fixCommits = @($commits | Where-Object { $_.isFix })
    $fixChains  = 0
    for ($i = 0; $i -lt $fixCommits.Count - 1; $i++) {
        $a = $fixCommits[$i]
        $b = $fixCommits[$i + 1]
        $dA = [DateTime]::MinValue; $dB = [DateTime]::MinValue
        [DateTime]::TryParse($a.dateStr, [ref]$dA) | Out-Null
        [DateTime]::TryParse($b.dateStr, [ref]$dB) | Out-Null
        if (($dA - $dB).TotalHours -le 48 -and $dA -gt $dB) {
            # Two fixes within 48h — check file overlap
            $filesA = @(& git -C $RepoRoot diff-tree --no-commit-id -r --name-only $a.hash 2>$null)
            $filesB = @(& git -C $RepoRoot diff-tree --no-commit-id -r --name-only $b.hash 2>$null)
            $overlap = @($filesA | Where-Object { $filesB -contains $_ })
            if ($overlap.Count -gt 0) { $fixChains++ }
        }
    }
    $fixOfFixScore = [Math]::Min(1.0, $fixChains * 0.35)
    [void]$signals.Add([ordered]@{ signal = 'fix-of-fix-chain'; value = $fixChains; score = [Math]::Round($fixOfFixScore,3) })
    [void]$checks.Add([ordered]@{ name = 'S1-fix-of-fix'; status = 'ok'; detail = "chains=$fixChains score=$fixOfFixScore" })
} catch {
    [void]$warnings.Add("fix-of-fix detection failed: $($_.Exception.Message)")
    [void]$checks.Add([ordered]@{ name = 'S1-fix-of-fix'; status = 'warn'; detail = 'git unavailable' })
}

# ── SIGNAL 2: High-churn files in last 72h ────────────────────────────────────
# Files changed more than N times in 72h = instability / incomplete understanding

$churnScore = 0.0
try {
    $recentLog = @(& git -C $RepoRoot log --format='%H' --since='3 days ago' 2>$null | Where-Object { $_ -match '\S' })
    $fileCounts = [System.Collections.Generic.Dictionary[string,int]]::new()
    foreach ($hash in $recentLog) {
        $f = @(& git -C $RepoRoot diff-tree --no-commit-id -r --name-only $hash 2>$null | Where-Object { $_ -match '\S' })
        foreach ($file in $f) {
            $fileCounts[$file] = ($fileCounts[$file] -as [int]) + 1
        }
    }
    $hotFiles = @($fileCounts.GetEnumerator() | Where-Object { $_.Value -ge 4 })
    $churnScore = [Math]::Min(1.0, $hotFiles.Count * 0.25)
    [void]$signals.Add([ordered]@{ signal = 'high-churn-72h'; value = $hotFiles.Count; score = [Math]::Round($churnScore,3); detail = ($hotFiles | Select-Object -First 3 | ForEach-Object { "$($_.Key)=$($_.Value)x" }) -join ', ' })
    [void]$checks.Add([ordered]@{ name = 'S2-churn'; status = 'ok'; detail = "hot-files=$($hotFiles.Count) score=$churnScore" })
} catch {
    [void]$warnings.Add("churn detection failed: $($_.Exception.Message)")
    [void]$checks.Add([ordered]@{ name = 'S2-churn'; status = 'warn'; detail = 'git unavailable' })
}

# ── SIGNAL 3: Commit burst — too many commits too fast ────────────────────────
# >15 commits in 24h = cognitive overload / insufficient review signal

$burstScore = 0.0
try {
    $recent24h = @(& git -C $RepoRoot log --format='%H' --since='24 hours ago' 2>$null | Where-Object { $_ -match '\S' })
    $burstCount = $recent24h.Count
    $burstScore = [Math]::Min(1.0, [Math]::Max(0, ($burstCount - 10)) * 0.06)
    [void]$signals.Add([ordered]@{ signal = 'commit-burst-24h'; value = $burstCount; score = [Math]::Round($burstScore,3) })
    [void]$checks.Add([ordered]@{ name = 'S3-burst'; status = 'ok'; detail = "commits-24h=$burstCount score=$burstScore" })
} catch {
    [void]$warnings.Add("burst detection failed: $($_.Exception.Message)")
    [void]$checks.Add([ordered]@{ name = 'S3-burst'; status = 'warn'; detail = 'git unavailable' })
}

# ── SIGNAL 4: Validation failure rate from history ────────────────────────────

$validationScore = 0.0
$histPath = Join-Path $RepoRoot 'logs/validation-history.jsonl'
try {
    if (Test-Path -LiteralPath $histPath) {
        $recent = [System.Collections.Generic.List[object]]::new()
        $cutoff = [DateTime]::UtcNow.AddDays(-7)
        foreach ($line in (Get-Content -LiteralPath $histPath -Encoding utf8)) {
            if (-not $line.Trim()) { continue }
            try {
                $r = $line | ConvertFrom-Json
                $ts = [DateTime]::MinValue
                if ([DateTime]::TryParse([string]$r.timestamp, [ref]$ts) -and $ts -ge $cutoff) {
                    [void]$recent.Add($r)
                }
            } catch { }
        }
        if ($recent.Count -ge 3) {
            $failCount = @($recent | Where-Object { [string]$_.status -in @('fail','error') }).Count
            $failRate  = $failCount / $recent.Count
            $validationScore = [Math]::Min(1.0, $failRate * 2.0)
            [void]$signals.Add([ordered]@{ signal = 'validation-failure-rate-7d'; value = [Math]::Round($failRate,3); score = [Math]::Round($validationScore,3); detail = "$failCount/$($recent.Count) failed" })
        }
    }
    [void]$checks.Add([ordered]@{ name = 'S4-validation'; status = 'ok'; detail = "score=$validationScore" })
} catch {
    [void]$warnings.Add("validation history read failed: $($_.Exception.Message)")
    [void]$checks.Add([ordered]@{ name = 'S4-validation'; status = 'warn'; detail = 'history unavailable' })
}

# ── Composite score ────────────────────────────────────────────────────────────
# Weighted: fix-of-fix 35%, churn 25%, burst 20%, validation 20%

$score = [Math]::Round(
    $fixOfFixScore   * 0.35 +
    $churnScore      * 0.25 +
    $burstScore      * 0.20 +
    $validationScore * 0.20,
    3
)

$gate        = if ($score -gt $BlockScore) { 'BLOCK' } elseif ($score -gt $WarnScore) { 'ADVISORY' } else { 'CLEAR' }
$blocked     = ($gate -eq 'BLOCK') -and (-not $forceVelocity)
$riskLabel   = if ($score -ge $BlockScore) { 'HIGH' } elseif ($score -ge $WarnScore) { 'MODERATE' } else { 'LOW' }

$recommendation = switch ($gate) {
    'BLOCK'    { 'Halt new changes. Stabilise the system: fix failing tests, reduce churn, investigate fix-of-fix cycles.' }
    'ADVISORY' { 'Slow down. Review changes carefully. Prefer small, isolated, well-tested commits.' }
    'CLEAR'    { 'Change velocity is within safe parameters.' }
}

if ($blocked) {
    [void]$failures.Add("Change velocity score $score > block threshold $BlockScore — $recommendation")
}

$sw.Stop()
$st = if ($blocked) { 'fail' } elseif ($gate -eq 'ADVISORY') { 'warn' } else { 'ok' }

$env = New-OsValidatorEnvelope -Tool 'change-velocity-gate' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        score          = $score
        riskLabel      = $riskLabel
        gate           = $gate
        blocked        = $blocked
        forceVelocity  = $forceVelocity
        signals        = @($signals)
        recommendation = $recommendation
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
} else {
    Write-Host "change-velocity-gate | score=$score | risk=$riskLabel | gate=$gate"
    foreach ($s in $signals) { Write-Host "  [$($s.signal)] value=$($s.value) contribution=$($s.score)" }
    Write-Host "  $recommendation"
    if ($blocked) { Write-Host "  Override: set CLAUDE_OS_FORCE_VELOCITY=1" }
}

if ($blocked) { exit 1 }
exit 0
