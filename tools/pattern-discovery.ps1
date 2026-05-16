# pattern-discovery.ps1 — Automated correlation mining from git history
# Discovers co-modification, cascade, and temporal patterns humans miss.
# Writes .claude/discovered-patterns.json; promote strong patterns to heuristics.
#   pwsh ./tools/pattern-discovery.ps1 -Mode discover
#   pwsh ./tools/pattern-discovery.ps1 -Mode report
#   pwsh ./tools/pattern-discovery.ps1 -Mode promote -PatternId DISC-001
#   pwsh ./tools/pattern-discovery.ps1 -Json

param(
    [ValidateSet('discover','promote','report')]
    [string]$Mode = 'report',
    [string]$PatternId = '',
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

$PatternsPath   = Join-Path $RepoRoot '.claude/discovered-patterns.json'
$HeuristicsPath = Join-Path $RepoRoot '.claude/heuristics/operational.md'
$DecisionPath   = Join-Path $RepoRoot '.claude/decision-log.jsonl'

function Get-Patterns {
    if (Test-Path -LiteralPath $PatternsPath) {
        try { return Get-Content -LiteralPath $PatternsPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { }
    }
    return [PSCustomObject]@{ patterns = @(); last_run = $null }
}

function Save-Patterns {
    param([object]$Data)
    $json = $Data | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($PatternsPath, ($json -replace "`r`n", "`n"), [System.Text.Encoding]::UTF8)
}

function Get-NextId {
    param([object[]]$Existing, [string]$Prefix)
    $maxN = 0
    foreach ($p in $Existing) {
        if ($p.id -match "^${Prefix}-(\d+)$") { $n = [int]$Matches[1]; if ($n -gt $maxN) { $maxN = $n } }
    }
    return $maxN + 1
}

# ── MODE: discover ────────────────────────────────────────────────────────────

if ($Mode -eq 'discover') {
    Push-Location $RepoRoot
    try {
        $data    = Get-Patterns
        $today   = (Get-Date).ToString('yyyy-MM-dd')
        $nowTs   = (Get-Date).ToUniversalTime().ToString('o')
        $nextId  = Get-NextId -Existing @($data.patterns) -Prefix 'DISC'

        # PHASE 1: Extract commits (last 200)
        $rawLog = & git log --format='%H|%ae|%s|%cd' --date=short -200 2>$null
        $commits = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $rawLog) {
            $p = $line -split '\|', 4
            if ($p.Count -lt 4) { continue }
            [void]$commits.Add([PSCustomObject]@{
                hash   = $p[0]
                email  = $p[1]
                msg    = $p[2]
                date   = $p[3]
                is_fix = ($p[2] -match '\b(fix|bug|revert|hotfix|patch)\b')
            })
        }

        # Per-commit file lists
        $commitFiles = [System.Collections.Generic.Dictionary[string,string[]]]::new()
        foreach ($c in $commits) {
            $files = & git diff-tree --no-commit-id -r --name-only $c.hash 2>$null
            $commitFiles[$c.hash] = @($files | Where-Object { $_ })
        }

        # PHASE 2a: CO-MODIFICATION patterns — P(B modified | A modified)
        $coMod     = [System.Collections.Generic.Dictionary[string,int]]::new()
        $fileCount = [System.Collections.Generic.Dictionary[string,int]]::new()

        foreach ($c in $commits) {
            $fs = $commitFiles[$c.hash]
            foreach ($f in $fs) {
                if (-not $fileCount.ContainsKey($f)) { $fileCount[$f] = 0 }
                $fileCount[$f]++
            }
            for ($i = 0; $i -lt $fs.Count; $i++) {
                for ($j = $i + 1; $j -lt $fs.Count; $j++) {
                    $key = "$($fs[$i])|$($fs[$j])"
                    if (-not $coMod.ContainsKey($key)) { $coMod[$key] = 0 }
                    $coMod[$key]++
                }
            }
        }

        $newPatterns = [System.Collections.Generic.List[object]]::new()

        # Emit co-modification patterns with P(B|A) > 0.6 and N >= 3
        foreach ($kv in $coMod.GetEnumerator()) {
            if ($kv.Value -lt 3) { continue }
            $ab = $kv.Key -split '\|', 2
            $a = $ab[0]; $b = $ab[1]
            $aCount = if ($fileCount.ContainsKey($a)) { [Math]::Max(1, $fileCount[$a]) } else { 1 }
            $pBA    = [Math]::Round($kv.Value / $aCount, 3)
            if ($pBA -lt 0.6) { continue }

            # Skip if already discovered
            $dup = @($data.patterns | Where-Object { $_.type -eq 'co_modification' -and ($_.files -contains $a) -and ($_.files -contains $b) }).Count
            if ($dup -gt 0) { continue }

            [void]$newPatterns.Add([PSCustomObject]@{
                id                 = "DISC-$('{0:D3}' -f $nextId++)"
                type               = 'co_modification'
                description        = "Implicit coupling: modifying ${a} correlates with modifying ${b} (P=${pBA})"
                files              = @($a, $b)
                strength           = $pBA
                observations       = $kv.Value
                first_seen         = $today
                last_seen          = $today
                proposed_heuristic = "H-DISC-$('{0:D3}' -f ($nextId - 1))"
                status             = 'pending_review'
            })
        }

        # PHASE 2b: CASCADE patterns — fix of A followed same-day by fix of B (freq > 0.4)
        $fixCommits   = @($commits | Where-Object { $_.is_fix })
        $cascadeCount = [System.Collections.Generic.Dictionary[string,int]]::new()

        for ($i = 0; $i -lt $fixCommits.Count; $i++) {
            $ci = $fixCommits[$i]
            for ($j = $i + 1; $j -lt [Math]::Min($i + 6, $fixCommits.Count); $j++) {
                $cj = $fixCommits[$j]
                if ($ci.date -ne $cj.date) { continue }  # same day = cascade candidate
                foreach ($fi in $commitFiles[$ci.hash]) {
                    foreach ($fj in $commitFiles[$cj.hash]) {
                        if ($fi -ne $fj) {
                            $key = "${fi}|${fj}"
                            if (-not $cascadeCount.ContainsKey($key)) { $cascadeCount[$key] = 0 }
                            $cascadeCount[$key]++
                        }
                    }
                }
            }
        }

        foreach ($kv in $cascadeCount.GetEnumerator()) {
            if ($kv.Value -lt 2) { continue }
            $ab = $kv.Key -split '\|', 2
            $a = $ab[0]; $b = $ab[1]
            $aFixes = @($fixCommits | Where-Object { ($commitFiles[$_.hash]) -contains $a }).Count
            $pCascade = if ($aFixes -gt 0) { [Math]::Round($kv.Value / $aFixes, 3) } else { 0 }
            if ($pCascade -lt 0.4) { continue }

            $dup = @($data.patterns | Where-Object { $_.type -eq 'cascade_risk' -and ($_.files -contains $a) -and ($_.files -contains $b) }).Count
            if ($dup -gt 0) { continue }

            [void]$newPatterns.Add([PSCustomObject]@{
                id                 = "DISC-$('{0:D3}' -f $nextId++)"
                type               = 'cascade_risk'
                description        = "Cascade risk: fixing ${a} often requires fixing ${b} within the same day"
                files              = @($a, $b)
                strength           = $pCascade
                observations       = $kv.Value
                first_seen         = $today
                last_seen          = $today
                proposed_heuristic = "H-DISC-$('{0:D3}' -f ($nextId - 1))"
                status             = 'pending_review'
            })
        }

        # PHASE 3: Merge and validate (only patterns with strength >= 0.6 and N >= 3)
        $validated = @($newPatterns | Where-Object { [double]$_.strength -ge 0.6 -and [int]$_.observations -ge 3 })

        $merged = [System.Collections.Generic.List[object]]::new()
        foreach ($p in @($data.patterns)) { [void]$merged.Add($p) }
        foreach ($p in $validated)        { [void]$merged.Add($p) }

        $updated = [PSCustomObject]@{ patterns = @($merged); last_run = $nowTs }
        Save-Patterns -Data $updated

        [void]$checks.Add([ordered]@{ name = 'discover'; status = 'ok'; detail = "commits=$($commits.Count) new=$($validated.Count) total=$($merged.Count)" })
        $env = New-OsValidatorEnvelope -Tool 'pattern-discovery' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
            -Findings @([ordered]@{ commits_analysed = $commits.Count; new_patterns = $validated.Count; total_patterns = $merged.Count })
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host "pattern-discovery | discover | commits=$($commits.Count) new=$($validated.Count) total=$($merged.Count)" }
    } finally { Pop-Location }
    exit 0
}

# ── MODE: report ──────────────────────────────────────────────────────────────

if ($Mode -eq 'report') {
    $data     = Get-Patterns
    $pending  = @($data.patterns | Where-Object { $_.status -eq 'pending_review' } |
                  Sort-Object { [double]$_.strength * [int]$_.observations } -Descending)
    $promoted = @($data.patterns | Where-Object { $_.status -eq 'promoted' })

    [void]$checks.Add([ordered]@{ name = 'report'; status = 'ok'; detail = "pending=$($pending.Count) promoted=$($promoted.Count)" })
    $env = New-OsValidatorEnvelope -Tool 'pattern-discovery' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Findings @([ordered]@{ pending = @($pending | Select-Object -First 10); promoted = @($promoted); total = @($data.patterns).Count })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else {
        Write-Host "pattern-discovery | report | pending=$($pending.Count) promoted=$($promoted.Count)"
        Write-Host ''
        foreach ($p in ($pending | Select-Object -First 10)) {
            Write-Host "  [$($p.id)] $($p.type) strength=$($p.strength) N=$($p.observations)"
            Write-Host "    $($p.description)"
        }
    }
    exit 0
}

# ── MODE: promote ─────────────────────────────────────────────────────────────

if ($Mode -eq 'promote') {
    if (-not $PatternId) {
        [void]$failures.Add('-PatternId required for promote mode')
        $env = New-OsValidatorEnvelope -Tool 'pattern-discovery' -Status 'fail' -DurationMs ([int]$sw.ElapsedMilliseconds) -Failures @($failures)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host 'pattern-discovery | promote | error: -PatternId required' }
        exit 0
    }

    $data    = Get-Patterns
    $pattern = $data.patterns | Where-Object { $_.id -eq $PatternId } | Select-Object -First 1
    if (-not $pattern) {
        [void]$failures.Add("Pattern ${PatternId} not found in discovered-patterns.json")
        $env = New-OsValidatorEnvelope -Tool 'pattern-discovery' -Status 'fail' -DurationMs ([int]$sw.ElapsedMilliseconds) -Failures @($failures)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host "pattern-discovery | promote | ${PatternId} not found" }
        exit 0
    }

    # Append to heuristics/operational.md
    if (Test-Path -LiteralPath $HeuristicsPath) {
        $fileList = $pattern.files -join ' / '
        $entry = @"


### $($pattern.proposed_heuristic) — Auto-promoted from pattern discovery ($($pattern.id))

**Evidence:** $($pattern.description) (N=$($pattern.observations), strength=$($pattern.strength), first_seen=$($pattern.first_seen))
**Rule:** When modifying ${fileList}, check co-changed files before committing. Pattern type: $($pattern.type).
**Apply:** Review both files together. Strength=$($pattern.strength) — high probability of required co-modification.
"@
        Add-Content -LiteralPath $HeuristicsPath -Value $entry -Encoding utf8
    }

    # Append to decision-log.jsonl
    if (Test-Path -LiteralPath $DecisionPath) {
        $decisionRecord = [ordered]@{
            ts      = (Get-Date).ToUniversalTime().ToString('o')
            type    = 'pattern-promotion'
            pattern = $PatternId
            heuristic = $pattern.proposed_heuristic
        }
        Add-Content -LiteralPath $DecisionPath -Value ($decisionRecord | ConvertTo-Json -Compress) -Encoding utf8
    }

    # Update status
    $pattern.status = 'promoted'
    $pattern | Add-Member -MemberType NoteProperty -Name 'promoted_at' -Value ((Get-Date).ToString('yyyy-MM-dd')) -Force
    Save-Patterns -Data $data

    [void]$checks.Add([ordered]@{ name = 'promote'; status = 'ok'; detail = "${PatternId} -> $($pattern.proposed_heuristic)" })
    $env = New-OsValidatorEnvelope -Tool 'pattern-discovery' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Findings @([ordered]@{ pattern_id = $PatternId; heuristic = $pattern.proposed_heuristic; promoted = $true })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else { Write-Host "pattern-discovery | promote | ${PatternId} -> $($pattern.proposed_heuristic)" }
    exit 0
}

exit 0
