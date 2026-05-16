# predictive-intervention.ps1 — Pre-push intervention: 4 predictions, consolidated risk score
# Blocks if score > 0.85, warns if 0.70-0.85, silent if < 0.70.
# Override: set CLAUDE_OS_FORCE_PUSH=1 environment variable.
#   pwsh ./tools/predictive-intervention.ps1
#   pwsh ./tools/predictive-intervention.ps1 -Json

param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$blockThreshold = 0.85
$warnThreshold  = 0.70
$forcePush      = ($env:CLAUDE_OS_FORCE_PUSH -eq '1')

# ── Get files being pushed ────────────────────────────────────────────────────
$diffFiles = @()
try {
    $vsOrigin = @(& git -C $RepoRoot diff --name-only origin/HEAD 2>$null | Where-Object { $_ -match '\S' })
    $staged   = @(& git -C $RepoRoot diff --cached --name-only 2>$null | Where-Object { $_ -match '\S' })
    $diffFiles = @($vsOrigin + $staged | Sort-Object -Unique)
    [void]$checks.Add([ordered]@{ name = 'diff-files'; status = 'ok'; detail = "$($diffFiles.Count) file(s)" })
} catch {
    [void]$warnings.Add("Could not get diff files: $($_.Exception.Message)")
    [void]$checks.Add([ordered]@{ name = 'diff-files'; status = 'warn'; detail = 'git unavailable' })
}

if ($diffFiles.Count -eq 0) {
    $sw.Stop()
    $env = New-OsValidatorEnvelope -Tool 'predictive-intervention' -Status 'ok' `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Failures @() `
        -Findings @(@([ordered]@{ score = 0; intervention = 'NONE'; files = 0 }))
    if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
    exit 0
}

$diffNames = @($diffFiles | ForEach-Object { [System.IO.Path]::GetFileName($_) })

# ── Load supporting data ───────────────────────────────────────────────────────
$graph = $null
$graphPath = Join-Path $RepoRoot '.claude/script-graph.json'
if (Test-Path -LiteralPath $graphPath) {
    try { $graph = (Get-Content -LiteralPath $graphPath -Raw -Encoding utf8) | ConvertFrom-Json } catch { }
}

$baselines = $null
$baselinePath = Join-Path $RepoRoot '.claude/learned-baselines.json'
if (Test-Path -LiteralPath $baselinePath) {
    try { $baselines = (Get-Content -LiteralPath $baselinePath -Raw -Encoding utf8) | ConvertFrom-Json } catch { }
}

$crossEvidence = $null
$evidencePath = Join-Path $RepoRoot 'heuristics/cross-project-evidence.json'
if (Test-Path -LiteralPath $evidencePath) {
    try { $crossEvidence = (Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8) | ConvertFrom-Json } catch { }
}

$predictions = [System.Collections.Generic.List[object]]::new()
$totalScore  = 0.0
$scoreCount  = 0

# ── PREDICTION 1: Invariant Impact ────────────────────────────────────────────
$invAtRisk = [System.Collections.Generic.List[object]]::new()
$invDir = Join-Path $RepoRoot 'invariants'
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
                        if ($diffNames -contains [System.IO.Path]::GetFileName([string]$tgt)) {
                            # Estimate P(violation) from learned baselines
                            $pViol = 0.5  # default
                            if ($baselines -and $baselines.file_risk_overrides) {
                                $matchFile = $diffFiles | Where-Object { [System.IO.Path]::GetFileName($_) -eq [System.IO.Path]::GetFileName([string]$tgt) } | Select-Object -First 1
                                if ($matchFile) {
                                    $prop = $baselines.file_risk_overrides.PSObject.Properties[$matchFile.Replace('\','/')]
                                    if ($prop) { $pViol = [Math]::Min(0.95, [double]$prop.Value * 1.5) }
                                }
                            }
                            [void]$invAtRisk.Add([ordered]@{ invariant = $ruleId; pViolation = [Math]::Round($pViol, 2) })
                            break
                        }
                    }
                }
            } catch { }
        }
    } catch { }
}

if ($invAtRisk.Count -gt 0) {
    $maxPViol = ($invAtRisk | ForEach-Object { [double]$_.pViolation } | Measure-Object -Maximum).Maximum
    [void]$predictions.Add([ordered]@{
        id     = 'invariant-impact'
        risk   = [Math]::Round($maxPViol, 2)
        detail = "$($invAtRisk.Count) invariant(s) at risk — highest P(violation)=$maxPViol"
        items  = @($invAtRisk)
    })
    $totalScore += $maxPViol; $scoreCount++
}
[void]$checks.Add([ordered]@{ name = 'P1-invariants'; status = 'ok'; detail = "$($invAtRisk.Count) at risk" })

# ── PREDICTION 2: Regression Probability ──────────────────────────────────────
$regressionRisk = [System.Collections.Generic.List[object]]::new()
foreach ($f in $diffFiles) {
    $pInc = 0.1  # static base
    if ($baselines -and $baselines.file_risk_overrides) {
        $norm = $f.Replace('\', '/')
        $prop = $baselines.file_risk_overrides.PSObject.Properties[$norm]
        if ($prop) { $pInc = [double]$prop.Value }
    }

    # Blast radius contribution
    $blastScore = 0.0
    if ($graph) {
        $name = [System.IO.Path]::GetFileName($f)
        $direct = @($graph.edges | Where-Object { [string]$_.to -eq $name }).Count
        $blastScore = [Math]::Min(1.0, $direct * 0.15)
    }

    $pRegress = [Math]::Min(1.0, $pInc * 0.7 + $blastScore * 0.3)
    if ($pRegress -gt 0.4) {
        [void]$regressionRisk.Add([ordered]@{ file = $f; pRegression = [Math]::Round($pRegress, 3) })
    }
}

if ($regressionRisk.Count -gt 0) {
    $maxReg = ($regressionRisk | ForEach-Object { [double]$_.pRegression } | Measure-Object -Maximum).Maximum
    [void]$predictions.Add([ordered]@{
        id     = 'regression-probability'
        risk   = [Math]::Round($maxReg, 2)
        detail = "$($regressionRisk.Count) file(s) with P(regression) > 0.4 — consider splitting this change"
        items  = @($regressionRisk)
    })
    $totalScore += $maxReg; $scoreCount++
}
[void]$checks.Add([ordered]@{ name = 'P2-regression'; status = 'ok'; detail = "$($regressionRisk.Count) high-regression files" })

# ── PREDICTION 3: Test Coverage Gap ───────────────────────────────────────────
$coverageGaps = [System.Collections.Generic.List[object]]::new()
foreach ($f in $diffFiles) {
    $base     = [System.IO.Path]::GetFileNameWithoutExtension($f)
    $testExists = $false
    foreach ($pattern in @("*.test.*", "*.spec.*", "*-tests.*", "*_test.*")) {
        $found = @(Get-ChildItem -LiteralPath $RepoRoot -Filter "$base$($pattern.Substring(1))" -Recurse -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { $testExists = $true; break }
    }

    if (-not $testExists) {
        $pInc = 0.1
        if ($baselines -and $baselines.file_risk_overrides) {
            $norm = $f.Replace('\', '/')
            $prop = $baselines.file_risk_overrides.PSObject.Properties[$norm]
            if ($prop) { $pInc = [double]$prop.Value }
        }
        if ($pInc -gt 0.25) {
            [void]$coverageGaps.Add([ordered]@{ file = $f; pIncident = [Math]::Round($pInc, 3) })
        }
    }
}

if ($coverageGaps.Count -gt 0) {
    $gapScore = [Math]::Min(0.6, $coverageGaps.Count * 0.15)
    [void]$predictions.Add([ordered]@{
        id     = 'coverage-gap'
        risk   = [Math]::Round($gapScore, 2)
        detail = "$($coverageGaps.Count) high-risk file(s) with no test coverage"
        items  = @($coverageGaps)
    })
    $totalScore += $gapScore; $scoreCount++
}
[void]$checks.Add([ordered]@{ name = 'P3-coverage'; status = 'ok'; detail = "$($coverageGaps.Count) gap(s)" })

# ── PREDICTION 4: Cross-Project Pattern Match ─────────────────────────────────
$patternMatches = [System.Collections.Generic.List[object]]::new()
if ($crossEvidence -and $crossEvidence.PSObject.Properties.Name -contains 'patterns') {
    foreach ($prop in $crossEvidence.patterns.PSObject.Properties) {
        $p = $prop.Value
        if ([int]$p.total -lt 2) { continue }
        # Check if any diff file matches a known pattern
        $sourceFile = if ($p.PSObject.Properties.Name -contains 'source_file') { [string]$p.source_file } else { '' }
        $matched = $false
        if ($sourceFile) {
            $sfName = [System.IO.Path]::GetFileName($sourceFile)
            if ($diffNames -contains $sfName) { $matched = $true }
        }
        # Tag-based match
        $patternKey = $prop.Name.ToLower()
        foreach ($name in $diffNames) {
            if ($patternKey -match [regex]::Escape($name.Replace('.ps1', '').Replace('.ts', '').Replace('.js', '').ToLower())) {
                $matched = $true
            }
        }
        if ($matched) {
            $ref = if ($p.PSObject.Properties.Name -contains 'heuristic_ref' -and $p.heuristic_ref) { " — see $($p.heuristic_ref)" } else { '' }
            [void]$patternMatches.Add([ordered]@{
                pattern = $prop.Name
                total   = [int]$p.total
                risk    = [string]$p.risk_if_ignored
                detail  = "KNOWN PATTERN: $($prop.Name) (confirmed in $([int]$p.total) project(s))$ref"
            })
        }
    }
}

if ($patternMatches.Count -gt 0) {
    $patternScore = [Math]::Min(0.5, $patternMatches.Count * 0.2)
    [void]$predictions.Add([ordered]@{
        id     = 'cross-project-pattern'
        risk   = [Math]::Round($patternScore, 2)
        detail = "$($patternMatches.Count) known cross-project pattern(s) matched"
        items  = @($patternMatches)
    })
    $totalScore += $patternScore; $scoreCount++
}
[void]$checks.Add([ordered]@{ name = 'P4-patterns'; status = 'ok'; detail = "$($patternMatches.Count) match(es)" })

# ── Consolidate score ─────────────────────────────────────────────────────────
$score          = if ($scoreCount -gt 0) { [Math]::Round([Math]::Min(1.0, $totalScore / $scoreCount), 3) } else { 0.0 }
$intervention   = if ($score -gt $blockThreshold) { 'BLOCK' } elseif ($score -gt $warnThreshold) { 'ADVISORY' } else { 'NONE' }
$riskLabel      = if ($score -ge 0.7) { 'ELEVATED' } elseif ($score -ge 0.4) { 'MODERATE' } else { 'LOW' }
$blocked        = ($intervention -eq 'BLOCK') -and (-not $forcePush)
$allPredictions = @($predictions)

$sw.Stop()
$st = if ($blocked) { 'fail' } elseif ($intervention -eq 'ADVISORY') { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'predictive-intervention' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @(if ($blocked) { @("Score $score > $blockThreshold — push blocked") } else { @() }) `
    -Findings @(@([ordered]@{
        score        = $score
        riskLabel    = $riskLabel
        intervention = $intervention
        blocked      = $blocked
        forcePush    = $forcePush
        files        = $diffFiles.Count
        predictions  = @($allPredictions)
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    if ($intervention -ne 'NONE') {
        Write-Host ''
        Write-Host '[OS-INTERVENTION] pre-push analysis'
        Write-Host "files: $($diffFiles.Count) | risk: $riskLabel | intervention: $intervention"
        if ($allPredictions.Count -gt 0) {
            Write-Host ''
            Write-Host 'PREDICTIONS:'
            foreach ($p in $allPredictions) { Write-Host "  $($p.detail)" }
        }
        Write-Host ''
        Write-Host "DECISION: $(if ($blocked) { "BLOCKED (score: $score > $blockThreshold threshold)" } else { "PROCEED with warnings (score: $score)" })"
        if ($blocked) {
            Write-Host "To override: set CLAUDE_OS_FORCE_PUSH=1 before pushing"
        } elseif ($intervention -eq 'ADVISORY') {
            Write-Host '[push continuing]'
        }
        Write-Host ''
    }
    # Document override in decision log
    if ($forcePush -and $intervention -eq 'BLOCK') {
        $decLog = Join-Path $RepoRoot '.claude/decision-log.jsonl'
        if (Test-Path -LiteralPath $decLog) {
            $override = [ordered]@{
                ts   = (Get-Date).ToUniversalTime().ToString('o')
                type = 'force_push_override'
                score = $score
                files = @($diffFiles)
            } | ConvertTo-Json -Compress
            Add-Content -LiteralPath $decLog -Value $override -Encoding utf8
        }
    }
}

if ($blocked) { exit 1 }
exit 0
