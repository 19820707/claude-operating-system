# slo-budget.ps1 — SLO error budget tracker from validation history
# Computes success rates (30d/7d/1d), error budget remaining, burn rate, and MTTR.
# Financial-grade reliability accounting: know your budget before it hits zero.
#   pwsh ./tools/slo-budget.ps1
#   pwsh ./tools/slo-budget.ps1 -SloTarget 0.99 -Json
#   pwsh ./tools/slo-budget.ps1 -Window 7

param(
    [double]$SloTarget  = 0.95,   # 95% success rate target
    [int]$Window        = 30,     # primary analysis window (days)
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

$histPath = Join-Path $RepoRoot 'logs/validation-history.jsonl'

# ── Parse validation history ──────────────────────────────────────────────────

$entries = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $histPath) {
    try {
        foreach ($line in (Get-Content -LiteralPath $histPath -Encoding utf8)) {
            if (-not $line.Trim()) { continue }
            try { [void]$entries.Add(($line | ConvertFrom-Json)) } catch { }
        }
    } catch {
        [void]$warnings.Add("Could not read validation-history.jsonl: $($_.Exception.Message)")
    }
}

[void]$checks.Add([ordered]@{ name = 'history-load'; status = 'ok'; detail = "$($entries.Count) record(s)" })

# If no history, return a baseline result — not an error
if ($entries.Count -eq 0) {
    [void]$warnings.Add('No validation history found — run os-validate -WriteHistory to start recording')
    $sw.Stop()
    $env = New-OsValidatorEnvelope -Tool 'slo-budget' -Status 'warn' `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Failures @() `
        -Findings @(@([ordered]@{
            sloTarget      = $SloTarget
            window         = $Window
            totalRuns      = 0
            successRate30d = $null
            successRate7d  = $null
            successRate1d  = $null
            budgetRemaining = $null
            burnRate        = $null
            mttrMinutes     = $null
            grade           = 'UNKNOWN'
            recommendation  = 'Start recording: os-validate -WriteHistory'
        }))
    if ($Json) { $env | ConvertTo-Json -Depth 10 -Compress | Write-Output }
    else { Write-Host 'slo-budget: no history yet — run os-validate -WriteHistory to begin tracking' }
    exit 0
}

# ── Window filtering ──────────────────────────────────────────────────────────

$now = [DateTime]::UtcNow

function Get-WindowEntries {
    param([int]$Days)
    $cutoff = $now.AddDays(-$Days)
    return @($entries | Where-Object {
        $ts = [DateTime]::MinValue
        if ([DateTime]::TryParse([string]$_.timestamp, [ref]$ts)) { $ts -ge $cutoff }
        else { $false }
    })
}

function Compute-Rate {
    param([object[]]$E)
    if (-not $E -or $E.Count -eq 0) { return $null }
    $ok = @($E | Where-Object { [string]$_.status -in @('ok','pass') }).Count
    return [Math]::Round($ok / $E.Count, 4)
}

$e30 = Get-WindowEntries -Days 30
$e7  = Get-WindowEntries -Days 7
$e1  = Get-WindowEntries -Days 1

$rate30 = Compute-Rate -E $e30
$rate7  = Compute-Rate -E $e7
$rate1  = Compute-Rate -E $e1

[void]$checks.Add([ordered]@{ name = 'rate-compute'; status = 'ok'; detail = "30d=$rate30 7d=$rate7 1d=$rate1" })

# ── Error budget ──────────────────────────────────────────────────────────────
# Budget = allowed failures in window = (1 - SloTarget) * total_runs
# Remaining = allowed - actual_failures

$budgetRemaining = $null
$burnRate        = $null

if ($rate30 -ne $null -and $e30.Count -ge 3) {
    $allowedFailureRate = 1.0 - $SloTarget
    $actualFailureRate  = 1.0 - $rate30
    # Budget remaining as % of the error budget (not total budget)
    if ($allowedFailureRate -gt 0) {
        $budgetRemaining = [Math]::Round([Math]::Max(0.0, 1.0 - ($actualFailureRate / $allowedFailureRate)), 4)
    } else {
        $budgetRemaining = if ($actualFailureRate -eq 0) { 1.0 } else { 0.0 }
    }

    # Burn rate: how fast are we consuming budget relative to expected pace?
    # Expected consumption per day = allowedFailureRate / 30
    # Actual consumption per day (7d) = (1 - rate7) / 7
    if ($rate7 -ne $null -and $e7.Count -ge 2 -and $allowedFailureRate -gt 0) {
        $expectedDailyBurn = $allowedFailureRate / 30.0
        $actualDailyBurn   = (1.0 - $rate7) / 7.0
        $burnRate = if ($expectedDailyBurn -gt 0) { [Math]::Round($actualDailyBurn / $expectedDailyBurn, 2) } else { $null }
    }
}

# ── MTTR: mean time between failure and next success ─────────────────────────

$mttrMinutes = $null
$sorted = @($entries | Sort-Object { [string]$_.timestamp })
$mttrSamples = [System.Collections.Generic.List[double]]::new()

for ($i = 0; $i -lt $sorted.Count - 1; $i++) {
    $cur = $sorted[$i]
    if ([string]$cur.status -notin @('ok','pass')) {
        # Find next success
        for ($j = $i + 1; $j -lt $sorted.Count; $j++) {
            $nxt = $sorted[$j]
            if ([string]$nxt.status -in @('ok','pass')) {
                $tCur = [DateTime]::MinValue
                $tNxt = [DateTime]::MinValue
                if ([DateTime]::TryParse([string]$cur.timestamp, [ref]$tCur) -and
                    [DateTime]::TryParse([string]$nxt.timestamp, [ref]$tNxt)) {
                    $diffMin = ($tNxt - $tCur).TotalMinutes
                    if ($diffMin -ge 0 -and $diffMin -le 1440) { [void]$mttrSamples.Add($diffMin) }
                }
                break
            }
        }
    }
}

if ($mttrSamples.Count -gt 0) {
    $mttrMinutes = [Math]::Round(($mttrSamples | Measure-Object -Average).Average, 1)
}

# ── Grade ─────────────────────────────────────────────────────────────────────

$primaryRate = if ($rate7 -ne $null) { $rate7 } elseif ($rate30 -ne $null) { $rate30 } else { $null }

$grade = 'UNKNOWN'
$recommendation = 'Insufficient data for grade'

if ($primaryRate -ne $null) {
    $grade = switch ($true) {
        ($primaryRate -ge 0.99)                          { 'A' }
        ($primaryRate -ge 0.95)                          { 'B' }
        ($primaryRate -ge 0.90)                          { 'C' }
        ($primaryRate -ge 0.80)                          { 'D' }
        default                                          { 'F' }
    }

    $burnLabel = if ($burnRate -ne $null) {
        if ($burnRate -gt 3.0) { " — burn rate ${burnRate}x (CRITICAL: budget draining fast)" }
        elseif ($burnRate -gt 1.5) { " — burn rate ${burnRate}x (ELEVATED)" }
        else { " — burn rate ${burnRate}x (nominal)" }
    } else { '' }

    $budgetLabel = if ($budgetRemaining -ne $null) {
        " | budget remaining $([Math]::Round($budgetRemaining * 100, 1))%"
    } else { '' }

    $recommendation = switch ($grade) {
        'A' { "Excellent reliability$burnLabel$budgetLabel" }
        'B' { "Within SLO target ($SloTarget)$burnLabel$budgetLabel — maintain current discipline" }
        'C' { "Below SLO target ($SloTarget)$burnLabel$budgetLabel — investigate recurring failures" }
        'D' { "Significantly below SLO$burnLabel$budgetLabel — prioritize stability over new features" }
        'F' { "Critical reliability issue$burnLabel$budgetLabel — halt new work; focus on recovery" }
    }
}

# Populate failures list if budget is exhausted
if ($budgetRemaining -ne $null -and $budgetRemaining -le 0) {
    [void]$failures.Add("Error budget exhausted (SLO target $SloTarget not met over ${Window}d window)")
}
if ($burnRate -ne $null -and $burnRate -gt 5.0) {
    [void]$failures.Add("Burn rate ${burnRate}x — budget will be exhausted in less than $('{0:F1}' -f (($window * (1-$SloTarget)) / ((1.0 - [double]($rate7 ?? $rate30)) / $window))) days")
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0 -or $grade -in @('C','D')) { 'warn' } else { 'ok' }

$finding = [ordered]@{
    sloTarget        = $SloTarget
    window           = $Window
    totalRuns        = $entries.Count
    successRate30d   = $rate30
    successRate7d    = $rate7
    successRate1d    = $rate1
    budgetRemaining  = $budgetRemaining
    burnRate         = $burnRate
    mttrMinutes      = $mttrMinutes
    grade            = $grade
    recommendation   = $recommendation
}

$env = New-OsValidatorEnvelope -Tool 'slo-budget' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@($finding))

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
} else {
    Write-Host "slo-budget | grade=$grade | SLO target=$SloTarget"
    Write-Host "  30d: $(if ($rate30 -ne $null){ "$([Math]::Round($rate30*100,1))%" }else{ 'n/a' })  7d: $(if ($rate7 -ne $null){ "$([Math]::Round($rate7*100,1))%" }else{ 'n/a' })  1d: $(if ($rate1 -ne $null){ "$([Math]::Round($rate1*100,1))%" }else{ 'n/a' })"
    if ($budgetRemaining -ne $null) { Write-Host "  error budget remaining: $([Math]::Round($budgetRemaining*100,1))%" }
    if ($burnRate -ne $null)        { Write-Host "  burn rate: ${burnRate}x" }
    if ($mttrMinutes -ne $null)     { Write-Host "  MTTR: ${mttrMinutes} min" }
    Write-Host "  $recommendation"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
