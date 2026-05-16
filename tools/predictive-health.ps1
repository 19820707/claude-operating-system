# predictive-health.ps1 — Pre-push risk scoring: churn, blast radius, exit hygiene, invariant risk
# Scores 0-100. Score > Threshold blocks push (exit 1). Use -Force to override.
#   pwsh ./tools/predictive-health.ps1
#   pwsh ./tools/predictive-health.ps1 -Json
#   pwsh ./tools/predictive-health.ps1 -Files tools/os-runtime.ps1,tools/os-validate.ps1
#   pwsh ./tools/predictive-health.ps1 -Threshold 80 -Force

param(
    [switch]$Json,
    [string[]]$Files = @(),
    [int]$Threshold = 70,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

# ── Determine touched files ────────────────────────────────────────────────────
if ($Files.Count -eq 0) {
    try {
        $vsOrigin  = @(& git -C $RepoRoot diff --name-only origin/HEAD 2>$null | Where-Object { $_ -match '\S' })
        $vsHead    = @(& git -C $RepoRoot diff --name-only HEAD 2>$null | Where-Object { $_ -match '\S' })
        $vsStaged  = @(& git -C $RepoRoot diff --cached --name-only 2>$null | Where-Object { $_ -match '\S' })
        $Files = @($vsOrigin + $vsHead + $vsStaged | Sort-Object -Unique)
    } catch {
        [void]$warnings.Add("Could not auto-detect touched files: $($_.Exception.Message)")
    }
}

if ($Files.Count -eq 0) {
    if (-not $Json) { Write-Host 'predictive-health: no touched files — nothing to score.' }
    [void]$checks.Add([ordered]@{ name = 'touched-files'; status = 'ok'; detail = '0 files' })
    $sw.Stop()
    $env = New-OsValidatorEnvelope -Tool 'predictive-health' -Status 'ok' `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
        -Findings @(@([ordered]@{ riskScore = 0; threshold = $Threshold; blocked = $false; recommendation = 'PROCEED' }))
    if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
    exit 0
}
[void]$checks.Add([ordered]@{ name = 'touched-files'; status = 'ok'; detail = "$($Files.Count) file(s)" })

# ── 1. Churn score (0-30) ─────────────────────────────────────────────────────
$churnScore = 0
$churnDetails = [ordered]@{}
try {
    $logLines = @(& git -C $RepoRoot log --oneline -30 --name-only --format='' 2>$null |
        Where-Object { $_ -match '\S' })
    $hitCount = @{}
    foreach ($l in $logLines) {
        $norm = $l.Replace('\', '/')
        $hitCount[$norm] = ($hitCount[$norm] -as [int]) + 1
    }
    $maxChurn = 0
    foreach ($f in $Files) {
        $norm = $f.Replace('\', '/')
        $c = if ($hitCount.ContainsKey($norm)) { [int]$hitCount[$norm] } else { 0 }
        $churnDetails[$norm] = $c
        if ($c -gt $maxChurn) { $maxChurn = $c }
    }
    $churnScore = if ($maxChurn -ge 8) { 30 } elseif ($maxChurn -ge 4) { 20 } elseif ($maxChurn -ge 1) { 10 } else { 0 }
    [void]$checks.Add([ordered]@{ name = 'churn'; status = 'ok'; detail = "maxChurn=$maxChurn score=$churnScore" })
} catch {
    [void]$warnings.Add("Churn analysis failed: $($_.Exception.Message)")
    [void]$checks.Add([ordered]@{ name = 'churn'; status = 'warn'; detail = 'skipped' })
}

# ── 2. Blast radius score (0-30) ──────────────────────────────────────────────
$blastScore   = 0
$blastAffected = @()
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
        $touched = @($Files | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Where-Object { $_ -match '\.ps1$' })
        $visited = [System.Collections.Generic.HashSet[string]]::new()
        $queue   = [System.Collections.Generic.Queue[string]]::new()
        foreach ($t in $touched) { [void]$queue.Enqueue($t) }
        while ($queue.Count -gt 0) {
            $node = $queue.Dequeue()
            if ($visited.Contains($node)) { continue }
            [void]$visited.Add($node)
            if ($revAdj.ContainsKey($node)) {
                foreach ($caller in $revAdj[$node]) { [void]$queue.Enqueue($caller) }
            }
        }
        $blastAffected = @($visited | Where-Object { $touched -notcontains $_ } | Sort-Object)
        $n = $blastAffected.Count
        $blastScore = if ($n -ge 10) { 30 } elseif ($n -ge 4) { 20 } elseif ($n -ge 1) { 10 } else { 0 }
        [void]$checks.Add([ordered]@{ name = 'blast-radius'; status = 'ok'; detail = "affected=$n score=$blastScore" })
    } catch {
        [void]$warnings.Add("Blast radius failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'blast-radius'; status = 'warn'; detail = 'error' })
    }
} else {
    [void]$warnings.Add('script-graph.json not found — run generate-script-graph.ps1 first')
    [void]$checks.Add([ordered]@{ name = 'blast-radius'; status = 'warn'; detail = 'no graph' })
}

# ── 3. Exit hygiene score (0-20) ──────────────────────────────────────────────
$hygieneScore    = 0
$hygieneSuspects = @()
$ps1Files = @($Files | Where-Object { $_ -match '(?i)tools[/\\].+\.ps1$' })
foreach ($f in $ps1Files) {
    $full = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $full)) { continue }
    try {
        $src = Get-Content -LiteralPath $full -Raw -Encoding utf8
        $hasFailPath = $src -match '(?m)^\s*exit\s+[1-9]|^\s*throw\s'
        $hasExit0    = $src -match '(?m)^\s*exit\s+0\s*$'
        if ($hasFailPath -and -not $hasExit0) { $hygieneSuspects += [System.IO.Path]::GetFileName($f) }
    } catch { }
}
$hygieneScore = if ($hygieneSuspects.Count -gt 0) { 20 } else { 0 }
[void]$checks.Add([ordered]@{
    name   = 'exit-hygiene'
    status = if ($hygieneScore -gt 0) { 'warn' } else { 'ok' }
    detail = "suspects=$($hygieneSuspects.Count) score=$hygieneScore"
})

# ── 4. Invariant risk score (0-20) ────────────────────────────────────────────
$invScore  = 0
$invAtRisk = @()
$invDir = Join-Path $RepoRoot 'invariants'
$touchedNames = @($Files | ForEach-Object { [System.IO.Path]::GetFileName($_) })
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
                            $invAtRisk += $ruleId; break
                        }
                    }
                }
            } catch { }
        }
        $invAtRisk = @($invAtRisk | Sort-Object -Unique)
        $invScore  = if ($invAtRisk.Count -ge 3) { 20 } elseif ($invAtRisk.Count -ge 1) { 10 } else { 0 }
        [void]$checks.Add([ordered]@{
            name   = 'invariant-risk'
            status = if ($invScore -gt 0) { 'warn' } else { 'ok' }
            detail = "atRisk=$($invAtRisk.Count) score=$invScore"
        })
    } catch {
        [void]$warnings.Add("Invariant risk failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'invariant-risk'; status = 'warn'; detail = 'error' })
    }
} else {
    [void]$checks.Add([ordered]@{ name = 'invariant-risk'; status = 'ok'; detail = 'no invariants dir' })
}

# ── Aggregate ─────────────────────────────────────────────────────────────────
$riskScore     = $churnScore + $blastScore + $hygieneScore + $invScore
$blocked       = ($riskScore -gt $Threshold) -and (-not $Force)
$recommendation = if ($riskScore -le 30) { 'PROCEED' } elseif ($riskScore -le 70) { 'REVIEW' } else { 'ESCALATE_TO_OPUS' }

if ($blocked) {
    [void]$failures.Add("RISK SCORE $riskScore > threshold $Threshold — push blocked. Run with -Force to override or address issues first.")
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'predictive-health' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        riskScore        = $riskScore
        threshold        = $Threshold
        blocked          = $blocked
        recommendation   = $recommendation
        breakdown        = [ordered]@{ churn = $churnScore; blastRadius = $blastScore; exitHygiene = $hygieneScore; invariants = $invScore }
        blastAffected    = $blastAffected
        hygieneSuspects  = $hygieneSuspects
        invariantsAtRisk = $invAtRisk
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'predictive-health'
    Write-Host "Files     : $($Files.Count) touched"
    Write-Host ''
    Write-Host "RISK SCORE : $riskScore / 100  [$recommendation]"
    Write-Host "  Churn        : $churnScore / 30"
    Write-Host "  Blast radius : $blastScore / 30  ($($blastAffected.Count) transitive callers)"
    Write-Host "  Exit hygiene : $hygieneScore / 20  ($($hygieneSuspects.Count) suspects)"
    Write-Host "  Invariants   : $invScore / 20  ($($invAtRisk.Count) at risk)"
    if ($blastAffected.Count -gt 0) { Write-Host "  Blast scope: $($blastAffected -join ', ')" }
    if ($hygieneSuspects.Count -gt 0) { Write-Host "  Hygiene suspects: $($hygieneSuspects -join ', ')" }
    if ($invAtRisk.Count -gt 0) { Write-Host "  Invariants: $($invAtRisk -join ', ')" }
    if ($blocked) {
        Write-Host ''
        Write-Host "BLOCKED: score $riskScore exceeds threshold $Threshold. Fix issues or use -Force to override."
    }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
