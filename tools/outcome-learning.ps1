# outcome-learning.ps1 — Correlates git outcomes to file risk; updates learned baselines
# Analyzes fix/revert commits that follow file changes within 7 days.
#   pwsh ./tools/outcome-learning.ps1 -Mode calibrate
#   pwsh ./tools/outcome-learning.ps1 -Mode report
#   pwsh ./tools/outcome-learning.ps1 -Mode promote-heuristic
#   pwsh ./tools/outcome-learning.ps1 -Json

param(
    [ValidateSet('calibrate', 'report', 'promote-heuristic')]
    [string]$Mode = 'calibrate',
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$baselinePath   = Join-Path $RepoRoot '.claude/learned-baselines.json'
$heuristicsPath = Join-Path $RepoRoot '.claude/heuristics/operational.md'
$findings       = [ordered]@{ mode = $Mode }

# ── Load existing baselines ────────────────────────────────────────────────────
function Load-Baselines {
    if (Test-Path -LiteralPath $baselinePath) {
        try { return (Get-Content -LiteralPath $baselinePath -Raw -Encoding utf8) | ConvertFrom-Json }
        catch { }
    }
    return [ordered]@{ file_risk_overrides = [ordered]@{}; coupled_risks = @(); last_calibrated = '' }
}

# ── Mode: calibrate ───────────────────────────────────────────────────────────
if ($Mode -eq 'calibrate') {
    try {
        # Get all commits in the last 90 days with their files and timestamps
        $logLines = @(& git -C $RepoRoot log --format='%H|%ae|%cd|%s' --date=iso --since='90 days ago' 2>$null | Where-Object { $_ -match '\S' })

        $commitData = [System.Collections.Generic.List[object]]::new()
        foreach ($l in $logLines) {
            $parts = $l -split '\|', 4
            if ($parts.Count -lt 4) { continue }
            $hash    = $parts[0].Trim()
            $author  = $parts[1].Trim()
            $dateStr = $parts[2].Trim()
            $subject = $parts[3].Trim()
            $isFix   = $subject -match '(?i)\bfix|revert|incident\b'
            [void]$commitData.Add([ordered]@{ hash = $hash; author = $author; date = $dateStr; subject = $subject; isFix = $isFix; files = @() })
        }

        # Get files for each commit
        foreach ($c in $commitData) {
            try {
                $cFiles = @(& git -C $RepoRoot diff-tree --no-commit-id -r --name-only $c.hash 2>$null | Where-Object { $_ -match '\S' })
                $c.files = $cFiles
            } catch { }
        }

        [void]$checks.Add([ordered]@{ name = 'load-commits'; status = 'ok'; detail = "$($commitData.Count) commits in 90d" })

        # Per-file: count total modifications and fix-within-7d
        $fileStats = [System.Collections.Generic.Dictionary[string, ordered]]::new()
        for ($i = 0; $i -lt $commitData.Count; $i++) {
            $c = $commitData[$i]
            foreach ($f in $c.files) {
                if (-not $fileStats.ContainsKey($f)) {
                    $fileStats[$f] = [ordered]@{ total = 0; fix_within_7d = 0 }
                }
                $fileStats[$f].total++

                # Check if any later commit (within 7 days) is a fix touching the same file
                if (-not $c.isFix) {
                    $cDate = [DateTime]::MinValue
                    [DateTime]::TryParse($c.date, [ref]$cDate) | Out-Null
                    for ($j = $i - 1; $j -ge 0; $j--) {
                        $later = $commitData[$j]
                        if (-not $later.isFix) { continue }
                        $lDate = [DateTime]::MinValue
                        [DateTime]::TryParse($later.date, [ref]$lDate) | Out-Null
                        $diff = ($lDate - $cDate).TotalDays
                        if ($diff -lt 0 -or $diff -gt 7) { continue }
                        if ($later.files -contains $f) { $fileStats[$f].fix_within_7d++; break }
                    }
                }
            }
        }

        # Compute P(incident|file) and store in baselines
        $baselines  = Load-Baselines
        $overrides  = [ordered]@{}
        $highRisk   = [System.Collections.Generic.List[object]]::new()

        foreach ($kv in $fileStats.GetEnumerator()) {
            $total = [int]$kv.Value.total
            $fixes = [int]$kv.Value.fix_within_7d
            if ($total -lt 2) { continue }  # not enough data
            $p = [Math]::Round($fixes / $total, 4)
            if ($p -gt 0.2) {  # only store meaningful overrides
                $overrides[$kv.Key] = $p
                if ($p -ge 0.4) { [void]$highRisk.Add([ordered]@{ file = $kv.Key; p_incident = $p; total = $total; fixes = $fixes }) }
            }
        }

        # Detect co-failure pairs
        $coupledRisks = [System.Collections.Generic.List[object]]::new()
        $fixCommits = @($commitData | Where-Object { $_.isFix })
        $pairCounts = [System.Collections.Generic.Dictionary[string, int]]::new()
        $pairTotal  = [System.Collections.Generic.Dictionary[string, int]]::new()

        foreach ($fc in $fixCommits) {
            $fFiles = @($fc.files | Where-Object { $overrides.ContainsKey($_) } | Sort-Object)
            for ($i = 0; $i -lt $fFiles.Count; $i++) {
                for ($j = $i + 1; $j -lt $fFiles.Count; $j++) {
                    $key = "$($fFiles[$i])|$($fFiles[$j])"
                    $pairCounts[$key] = ($pairCounts[$key] -as [int]) + 1
                }
            }
        }

        foreach ($kv in $pairCounts.GetEnumerator()) {
            if ([int]$kv.Value -ge 2) {
                $parts = $kv.Key -split '\|'
                $conf  = [Math]::Min(1.0, [double]$kv.Value / [Math]::Max(1, $fixCommits.Count))
                [void]$coupledRisks.Add(@($parts[0], $parts[1], $conf))
            }
        }

        # Save updated baselines
        $newBaselines = [ordered]@{
            file_risk_overrides = $overrides
            coupled_risks       = @($coupledRisks)
            last_calibrated     = (Get-Date).ToUniversalTime().ToString('o')
            high_risk_files     = @($highRisk)
        }
        if (-not $DryRun) { $newBaselines | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $baselinePath -Encoding utf8 }

        [void]$checks.Add([ordered]@{ name = 'calibrate'; status = 'ok'; detail = "overrides=$($overrides.Count) coupled=$($coupledRisks.Count)" })
        $findings.overrides    = $overrides.Count
        $findings.coupled      = $coupledRisks.Count
        $findings.highRiskFiles = @($highRisk)

        if (-not $Json) {
            Write-Host 'outcome-learning [calibrate]'
            Write-Host "Files with risk overrides: $($overrides.Count)"
            Write-Host "Coupled failure pairs    : $($coupledRisks.Count)"
            if ($highRisk.Count -gt 0) {
                Write-Host 'High-risk files (P >= 0.4):'
                foreach ($h in ($highRisk | Sort-Object { -[double]$_.p_incident })) {
                    Write-Host "  P=$($h.p_incident)  $($h.file)  (fixes=$($h.fixes)/$($h.total))"
                }
            }
        }
    } catch {
        [void]$warnings.Add("Calibration failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'calibrate'; status = 'warn'; detail = $_.Exception.Message })
    }
}

# ── Mode: report ──────────────────────────────────────────────────────────────
elseif ($Mode -eq 'report') {
    $baselines = Load-Baselines
    $overrides = $baselines.file_risk_overrides

    if (-not $overrides -or $overrides.PSObject.Properties.Count -eq 0) {
        [void]$warnings.Add('No learned baselines found — run --calibrate first')
        [void]$checks.Add([ordered]@{ name = 'report'; status = 'warn'; detail = 'no baselines' })
    } else {
        $rows = @($overrides.PSObject.Properties | ForEach-Object {
            [ordered]@{ file = $_.Name; p_incident = [double]$_.Value }
        } | Sort-Object { -[double]$_.p_incident })

        [void]$checks.Add([ordered]@{ name = 'report'; status = 'ok'; detail = "$($rows.Count) file(s) with learned risk" })
        $findings.calibrated  = [string]$baselines.last_calibrated
        $findings.fileRisks   = @($rows)
        $findings.coupledRisks = @($baselines.coupled_risks)

        if (-not $Json) {
            Write-Host 'outcome-learning [report]'
            Write-Host "Calibrated: $($baselines.last_calibrated)"
            Write-Host ''
            foreach ($r in $rows | Select-Object -First 10) {
                Write-Host "  P=$($r.p_incident.ToString('F3'))  $($r.file)"
            }
            if ($baselines.coupled_risks.Count -gt 0) {
                Write-Host ''
                Write-Host "Coupled failure pairs:"
                foreach ($cp in @($baselines.coupled_risks) | Select-Object -First 5) {
                    if ($cp.Count -ge 2) { Write-Host "  $($cp[0]) + $($cp[1])$(if ($cp.Count -ge 3) { "  (conf=$($cp[2])" })" }
                }
            }
        }
    }
}

# ── Mode: promote-heuristic ───────────────────────────────────────────────────
elseif ($Mode -eq 'promote-heuristic') {
    $baselines = Load-Baselines
    $coupled   = @($baselines.coupled_risks)
    $promoted  = [System.Collections.Generic.List[string]]::new()

    foreach ($pair in $coupled) {
        if ($pair.Count -lt 3) { continue }
        $conf = [double]$pair[2]
        $n    = [int](($baselines.file_risk_overrides.PSObject.Properties[$pair[0]].Value -as [double]) * 100)
        if ($conf -ge 0.7) {
            $entry = @"


---

### LEARNED-CO-FAIL — Co-failure: $($pair[0]) + $($pair[1])

**Evidence:** Files modified together with subsequent fix commit at confidence=$($conf.ToString('F2')) (auto-promoted $(Get-Date -Format 'yyyy-MM-dd') by outcome-learning).
**Rule:** When modifying $([System.IO.Path]::GetFileName($pair[0])), always review $([System.IO.Path]::GetFileName($pair[1])) for consistency — these files have co-failed before.
**Apply:** Run `pwsh ./tools/simulate-impact.ps1 -Files $($pair[0])` before pushing changes to either file.
"@
            if (Test-Path -LiteralPath $heuristicsPath) {
                $existing = Get-Content -LiteralPath $heuristicsPath -Raw -Encoding utf8
                if (-not ($existing -match [regex]::Escape("$($pair[0]) + $($pair[1])"))) {
                    $newContent = $existing.TrimEnd() + $entry + "`n"
                    [System.IO.File]::WriteAllText($heuristicsPath, $newContent, [System.Text.Encoding]::UTF8)
                    [void]$promoted.Add("$($pair[0]) + $($pair[1])")
                }
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'promote'; status = 'ok'; detail = "promoted=$($promoted.Count)" })
    $findings.promoted = @($promoted)

    if (-not $Json) {
        Write-Host "outcome-learning [promote-heuristic]"
        Write-Host "Promoted: $($promoted.Count)"
        foreach ($p in $promoted) { Write-Host "  + $p" }
        if ($promoted.Count -eq 0) { Write-Host '  (no pairs meet confidence>=0.7 threshold)' }
    }
}

$sw.Stop()
$st = if ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'outcome-learning' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @() `
    -Findings @(@($findings))

if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
exit 0
