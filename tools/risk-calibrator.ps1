# risk-calibrator.ps1 — Probabilistic file risk scoring from git history
# Computes P(incident) from churn, bug density, incident proximity, author count.
# Combines with blast radius from script-graph.json for a composite risk score.
#   pwsh ./tools/risk-calibrator.ps1 -Files tools/os-validate.ps1,tools/os-runtime.ps1
#   pwsh ./tools/risk-calibrator.ps1 -Scan
#   pwsh ./tools/risk-calibrator.ps1 -Scan -Threshold 0.7
#   pwsh ./tools/risk-calibrator.ps1 -Json

param(
    [string[]]$Files = @(),
    [switch]$Scan,
    [double]$Threshold = -1,
    [switch]$DryRun,
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

$riskProfilePath = Join-Path $RepoRoot '.claude/risk-profile.json'

# ── Auto-detect files in scan mode ────────────────────────────────────────────
if ($Scan) {
    try {
        $wt     = @(& git -C $RepoRoot diff --name-only 2>$null | Where-Object { $_ -match '\S' })
        $staged = @(& git -C $RepoRoot diff --cached --name-only 2>$null | Where-Object { $_ -match '\S' })
        $Files  = @($wt + $staged | Sort-Object -Unique)
        [void]$checks.Add([ordered]@{ name = 'scan'; status = 'ok'; detail = "$($Files.Count) file(s) in working tree" })
    } catch {
        [void]$warnings.Add("Scan failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'scan'; status = 'warn'; detail = 'git unavailable' })
    }
}

if ($Files.Count -eq 0) {
    if (-not $Json) { Write-Host 'risk-calibrator: no files to analyze.' }
    $sw.Stop()
    $env = New-OsValidatorEnvelope -Tool 'risk-calibrator' -Status 'ok' `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
        -Findings @(@([ordered]@{ filesAnalyzed = 0; maxRiskScore = 0; threshold = $Threshold }))
    if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
    exit 0
}

# ── Load script graph for blast radius ────────────────────────────────────────
$graphPath = Join-Path $RepoRoot '.claude/script-graph.json'
$revAdj = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new()
$allNodes = @()
if (Test-Path -LiteralPath $graphPath) {
    try {
        $graph = (Get-Content -LiteralPath $graphPath -Raw -Encoding utf8) | ConvertFrom-Json
        foreach ($edge in $graph.edges) {
            if (-not $revAdj.ContainsKey($edge.to)) { $revAdj[$edge.to] = [System.Collections.Generic.HashSet[string]]::new() }
            [void]$revAdj[$edge.to].Add($edge.from)
        }
        $allNodes = @($graph.nodes | ForEach-Object { [string]$_.id })
        [void]$checks.Add([ordered]@{ name = 'script-graph'; status = 'ok'; detail = "$($allNodes.Count) nodes" })
    } catch {
        [void]$warnings.Add("Script graph load failed: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'script-graph'; status = 'warn'; detail = 'load error' })
    }
} else {
    [void]$warnings.Add('script-graph.json not found — run generate-script-graph.ps1 for blast radius')
    [void]$checks.Add([ordered]@{ name = 'script-graph'; status = 'warn'; detail = 'missing' })
}

# ── Load learned baselines (from outcome-learning) ────────────────────────────
$learnedBaselines = $null
$baselinePath = Join-Path $RepoRoot '.claude/learned-baselines.json'
if (Test-Path -LiteralPath $baselinePath) {
    try { $learnedBaselines = (Get-Content -LiteralPath $baselinePath -Raw -Encoding utf8) | ConvertFrom-Json }
    catch { }
}

function Get-LearnedOverride {
    param([string]$File)
    if (-not $learnedBaselines) { return -1 }
    $overrides = $learnedBaselines.PSObject.Properties.Name -contains 'file_risk_overrides'
    if (-not $overrides) { return -1 }
    $key = $File.Replace('\', '/')
    $prop = $learnedBaselines.file_risk_overrides.PSObject.Properties[$key]
    if ($prop) { return [double]$prop.Value }
    return -1
}

# ── Blast radius calculation ───────────────────────────────────────────────────
function Get-BlastRadius {
    param([string]$ScriptName)
    $direct = 0
    if ($revAdj.ContainsKey($ScriptName)) { $direct = $revAdj[$ScriptName].Count }
    # DFS depth-2 for transitive
    $visited = [System.Collections.Generic.HashSet[string]]::new()
    $queue   = [System.Collections.Generic.Queue[string]]::new()
    [void]$queue.Enqueue($ScriptName)
    $depth = @{ $ScriptName = 0 }
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        if ($visited.Contains($node)) { continue }
        [void]$visited.Add($node)
        $d = [int]$depth[$node]
        if ($d -ge 2) { continue }
        if ($revAdj.ContainsKey($node)) {
            foreach ($caller in $revAdj[$node]) {
                if (-not $depth.ContainsKey($caller)) { $depth[$caller] = $d + 1 }
                [void]$queue.Enqueue($caller)
            }
        }
    }
    $transitive = [Math]::Max(0, $visited.Count - 1)
    $score = $direct * 1.0 + $transitive * 0.3
    return [ordered]@{ direct = $direct; transitive = $transitive; score = $score }
}

# ── Analyse each file ─────────────────────────────────────────────────────────
$fileResults = [System.Collections.Generic.List[object]]::new()
$maxScore    = 0.0

foreach ($f in $Files) {
    $rel  = $f.Replace('\', '/')
    $name = [System.IO.Path]::GetFileName($f)

    # Git metrics
    $churn             = 0
    $bugDensity        = 0
    $incidentProximity = 0
    $authorCount       = 1

    try {
        $churnLines = @(& git -C $RepoRoot log --oneline --since='90 days ago' --follow -- $rel 2>$null | Where-Object { $_ -match '\S' })
        $churn      = $churnLines.Count

        $bugLines = @(& git -C $RepoRoot log --oneline --follow --grep='fix|bug|hotfix|revert|incident' -- $rel 2>$null | Where-Object { $_ -match '\S' })
        $bugDensity = $bugLines.Count

        $incLines = @(& git -C $RepoRoot log --oneline --grep='incident|emergency|hotfix' -- $rel 2>$null | Where-Object { $_ -match '\S' })
        $incidentProximity = $incLines.Count

        $authors = @(& git -C $RepoRoot log --format='%ae' --follow -- $rel 2>$null | Where-Object { $_ -match '\S' } | Sort-Object -Unique)
        $authorCount = [Math]::Max(1, $authors.Count)
    } catch { }

    # P(incident) formula
    $base     = $bugDensity / [Math]::Max($churn, 1)
    $adjusted = $base * (1 + $incidentProximity * 0.5) * (1 + ($authorCount - 1) * 0.1)
    $pIncident = [Math]::Min(1.0, [Math]::Max(0.0, $adjusted))

    # Override from learned baselines
    $learnedOverride = Get-LearnedOverride -File $rel
    if ($learnedOverride -ge 0) { $pIncident = [Math]::Max($pIncident, $learnedOverride) }

    # Blast radius
    $blast = Get-BlastRadius -ScriptName $name
    $maxBlastPossible = [Math]::Max(1, $allNodes.Count)
    $blastNorm = [Math]::Min(1.0, [double]$blast.score / $maxBlastPossible)

    # Composite risk score
    $riskScore = $pIncident * 0.6 + $blastNorm * 0.4
    $riskScore = [Math]::Min(1.0, [Math]::Max(0.0, $riskScore))

    $level = if ($riskScore -ge 0.7) { 'CRITICAL' } elseif ($riskScore -ge 0.5) { 'ELEVATED' } elseif ($riskScore -ge 0.3) { 'MODERATE' } else { 'LOW' }

    if ($riskScore -gt $maxScore) { $maxScore = $riskScore }

    [void]$fileResults.Add([ordered]@{
        file              = $rel
        p_incident        = [Math]::Round($pIncident, 4)
        churn_90d         = $churn
        bug_density       = $bugDensity
        incident_proximity = $incidentProximity
        author_count      = $authorCount
        blast_radius      = [ordered]@{ direct = [int]$blast.direct; transitive = [int]$blast.transitive; score = [Math]::Round([double]$blast.score, 2) }
        risk_score        = [Math]::Round($riskScore, 4)
        level             = $level
        learned_override  = if ($learnedOverride -ge 0) { $learnedOverride } else { $null }
        calibration       = "based on $churn change(s) in 90d"
    })
}
[void]$checks.Add([ordered]@{ name = 'analyze'; status = 'ok'; detail = "$($fileResults.Count) file(s) analyzed, maxScore=$([Math]::Round($maxScore,3))" })

# ── Write risk profile ────────────────────────────────────────────────────────
if (-not $DryRun) {
    try {
        $profile = [ordered]@{
            generated = (Get-Date).ToUniversalTime().ToString('o')
            files     = @($fileResults)
            maxScore  = [Math]::Round($maxScore, 4)
        }
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $riskProfilePath -Encoding utf8
        [void]$checks.Add([ordered]@{ name = 'write-profile'; status = 'ok'; detail = $riskProfilePath })
    } catch {
        [void]$warnings.Add("Could not write risk-profile.json: $($_.Exception.Message)")
    }
} else {
    [void]$checks.Add([ordered]@{ name = 'write-profile'; status = 'ok'; detail = 'dry-run — skipped' })
}

# ── Threshold check ────────────────────────────────────────────────────────────
$thresholdExceeded = $Threshold -ge 0 -and $maxScore -gt $Threshold
if ($thresholdExceeded) {
    $exceeded = @($fileResults | Where-Object { [double]$_.risk_score -gt $Threshold })
    [void]$failures.Add("Threshold $Threshold exceeded by $($exceeded.Count) file(s): $($exceeded | ForEach-Object { "$($_.file) ($($_.level) $($_.risk_score))" })")
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'risk-calibrator' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        filesAnalyzed  = $fileResults.Count
        maxRiskScore   = [Math]::Round($maxScore, 4)
        threshold      = $Threshold
        exceeded       = $thresholdExceeded
        files          = @($fileResults)
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'risk-calibrator'
    foreach ($r in ($fileResults | Sort-Object { -[double]$_.risk_score })) {
        $bar = '█' * [Math]::Round([double]$r.risk_score * 10)
        Write-Host "  $($r.level.PadRight(8)) [$bar] $([Math]::Round([double]$r.risk_score * 100, 1))%  $($r.file)"
        Write-Host "           P(incident)=$($r.p_incident)  churn=$($r.churn_90d)  bugs=$($r.bug_density)  blast=$($r.blast_radius.direct)+$($r.blast_radius.transitive)"
    }
    if ($thresholdExceeded) { Write-Host "`nFAIL: threshold $Threshold exceeded" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
