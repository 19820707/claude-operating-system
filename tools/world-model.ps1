# world-model.ps1 — Internal probabilistic world model: entities, relations, Bayesian risk posteriors
# Maintains .claude/world-model.json — a living model of repository state with confidence decay.
#   pwsh ./tools/world-model.ps1 -Mode update
#   pwsh ./tools/world-model.ps1 -Mode query -Entity tools/verify-agent-adapters.ps1
#   pwsh ./tools/world-model.ps1 -Mode relations -Type implicit_coupling -MinStrength 0.3
#   pwsh ./tools/world-model.ps1 -Mode export-context -Files tools/auth.ps1,tools/billing.ps1
#   pwsh ./tools/world-model.ps1 -Json

param(
    [ValidateSet('update','query','relations','export-context')]
    [string]$Mode = 'query',
    [string]$Entity = '',
    [string[]]$Files = @(),
    [string]$Type = 'implicit_coupling',
    [double]$MinStrength = 0.3,
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

$ModelPath = Join-Path $RepoRoot '.claude/world-model.json'

# ── World model I/O ───────────────────────────────────────────────────────────

function Get-WorldModel {
    if (Test-Path -LiteralPath $ModelPath) {
        try { return Get-Content -LiteralPath $ModelPath -Raw -Encoding utf8 | ConvertFrom-Json }
        catch { }
    }
    return [PSCustomObject]@{
        entities     = [PSCustomObject]@{}
        relations    = @()
        global_state = [PSCustomObject]@{
            system_health       = 1.0
            learning_velocity   = 0.0
            prediction_accuracy = 0.0
            last_updated        = (Get-Date).ToString('yyyy-MM-dd')
        }
    }
}

function Save-WorldModel {
    param([object]$Model)
    $json = $Model | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($ModelPath, ($json -replace "`r`n", "`n"), [System.Text.Encoding]::UTF8)
}

function Get-OrCreateEntity {
    param([object]$Model, [string]$Key)
    $prop = $Model.entities.PSObject.Properties[$Key]
    if ($prop) { return $prop.Value }
    return [PSCustomObject]@{
        type             = 'script'
        state            = 'unknown'
        risk_posterior   = 0.3
        last_incident    = $null
        incident_count   = 0
        coupling         = @()
        causal_chain     = @()
        confidence_decay = 0.02
        last_updated     = (Get-Date).ToString('yyyy-MM-dd')
    }
}

function Set-Entity {
    param([object]$Model, [string]$Key, [object]$Value)
    $Model.entities | Add-Member -MemberType NoteProperty -Name $Key -Value $Value -Force
}

# ── Bayesian update: posterior = (L*P) / ((L*P) + (1-L)*(1-P)) ───────────────

function Update-Posterior {
    param([double]$Prior, [double]$Likelihood)
    $L = [Math]::Max(0.001, [Math]::Min(0.999, $Likelihood))
    $P = [Math]::Max(0.001, [Math]::Min(0.999, $Prior))
    $num = $L * $P
    return [Math]::Round($num / ($num + (1 - $L) * (1 - $P)), 4)
}

function Apply-Decay {
    param([double]$Risk, [double]$DecayRate, [string]$LastUpdated)
    try {
        $last = [datetime]::ParseExact($LastUpdated, 'yyyy-MM-dd', $null)
        $days = ([datetime]::Today - $last).TotalDays
        return [Math]::Max(0.05, [Math]::Round($Risk * (1 - $DecayRate * $days), 4))
    } catch { return $Risk }
}

# ── MODE: update ──────────────────────────────────────────────────────────────

if ($Mode -eq 'update') {
    Push-Location $RepoRoot
    try {
        $model = Get-WorldModel
        $today = (Get-Date).ToString('yyyy-MM-dd')

        # Parse git log last 30 commits
        $rawLog = & git log --format='%H|%s|%cd' --date=short -30 2>$null
        $commits = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $rawLog) {
            $p = $line -split '\|', 3
            if ($p.Count -lt 3) { continue }
            [void]$commits.Add([PSCustomObject]@{
                hash   = $p[0]
                msg    = $p[1]
                date   = $p[2]
                is_fix = ($p[1] -match '\b(fix|bug|revert|hotfix|patch)\b')
            })
        }

        # Per-commit file lists
        $commitFiles = [System.Collections.Generic.Dictionary[string,string[]]]::new()
        foreach ($c in $commits) {
            $files = & git diff-tree --no-commit-id -r --name-only $c.hash 2>$null
            $commitFiles[$c.hash] = @($files | Where-Object { $_ })
        }

        # Aggregate per-file churn and bug density
        $fileStats = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
        foreach ($c in $commits) {
            foreach ($f in $commitFiles[$c.hash]) {
                if (-not $fileStats.ContainsKey($f)) {
                    $fileStats[$f] = [PSCustomObject]@{ churn = 0; bug_count = 0 }
                }
                $fileStats[$f].churn++
                if ($c.is_fix) { $fileStats[$f].bug_count++ }
            }
        }

        # Co-modification pair frequency
        $coMod = [System.Collections.Generic.Dictionary[string,int]]::new()
        foreach ($c in $commits) {
            $fs = $commitFiles[$c.hash]
            for ($i = 0; $i -lt $fs.Count; $i++) {
                for ($j = $i + 1; $j -lt $fs.Count; $j++) {
                    $key = "$($fs[$i])|$($fs[$j])"
                    if (-not $coMod.ContainsKey($key)) { $coMod[$key] = 0 }
                    $coMod[$key]++
                }
            }
        }

        # Update entity risk posteriors with Bayesian update + decay
        foreach ($kv in $fileStats.GetEnumerator()) {
            $f     = $kv.Key
            $stats = $kv.Value
            $ent   = Get-OrCreateEntity -Model $model -Key $f

            $decayed  = Apply-Decay -Risk $ent.risk_posterior -DecayRate $ent.confidence_decay -LastUpdated $ent.last_updated
            $churn    = [Math]::Max(1, $stats.churn)
            $lhood    = [Math]::Min(0.95, $stats.bug_count / $churn)
            $newRisk  = Update-Posterior -Prior $decayed -Likelihood $lhood

            $ent.risk_posterior = $newRisk
            $ent.last_updated   = $today
            Set-Entity -Model $model -Key $f -Value $ent
        }

        # Upsert implicit coupling relations from co-modification data
        $relList = [System.Collections.Generic.List[object]]::new()
        foreach ($r in @($model.relations)) { [void]$relList.Add($r) }

        foreach ($kv in $coMod.GetEnumerator()) {
            if ($kv.Value -lt 2) { continue }
            $ab = $kv.Key -split '\|', 2
            $a = $ab[0]; $b = $ab[1]
            $aChurn   = if ($fileStats.ContainsKey($a)) { [Math]::Max(1, $fileStats[$a].churn) } else { 1 }
            $strength = [Math]::Round([Math]::Min(1.0, $kv.Value / $aChurn), 3)

            $existing = $relList | Where-Object { $_.from -eq $a -and $_.to -eq $b -and $_.type -eq 'implicit_coupling' } | Select-Object -First 1
            if ($existing) {
                $existing.strength       = [Math]::Round([Math]::Min(1.0, [double]$existing.strength + 0.05), 3)
                $existing.evidence_count = [int]$existing.evidence_count + $kv.Value
            } else {
                [void]$relList.Add([PSCustomObject]@{
                    from           = $a
                    to             = $b
                    type           = 'implicit_coupling'
                    strength       = $strength
                    evidence_count = $kv.Value
                    discovered     = $today
                })
            }
        }

        $model.relations             = @($relList)
        $model.global_state.last_updated = $today
        Save-WorldModel -Model $model

        [void]$checks.Add([ordered]@{ name = 'update'; status = 'ok'; detail = "entities=$($fileStats.Count) relations=$($relList.Count)" })
        $env = New-OsValidatorEnvelope -Tool 'world-model' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
            -Findings @([ordered]@{ mode = 'update'; entities_updated = $fileStats.Count; relations = $relList.Count })
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host "world-model | update | entities=$($fileStats.Count) relations=$($relList.Count)" }
    } finally { Pop-Location }
    exit 0
}

# ── MODE: query ───────────────────────────────────────────────────────────────

if ($Mode -eq 'query') {
    if (-not $Entity) {
        [void]$failures.Add('-Entity required for query mode')
        $env = New-OsValidatorEnvelope -Tool 'world-model' -Status 'fail' -DurationMs ([int]$sw.ElapsedMilliseconds) -Failures @($failures)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host 'world-model | query | error: -Entity required' }
        exit 0
    }
    $model = Get-WorldModel
    $ent   = Get-OrCreateEntity -Model $model -Key $Entity
    $predicted = [Math]::Round([double]$ent.risk_posterior * 1.1, 4)  # simple next-step estimate

    [void]$checks.Add([ordered]@{ name = 'query'; status = 'ok'; detail = $Entity })
    $finding = [ordered]@{
        entity                 = $Entity
        risk_posterior         = $ent.risk_posterior
        state                  = $ent.state
        incident_count         = $ent.incident_count
        causal_chains          = @($ent.causal_chain)
        coupling               = @($ent.coupling)
        predicted_next_failure = $predicted
        last_updated           = $ent.last_updated
    }
    $env = New-OsValidatorEnvelope -Tool 'world-model' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($checks) -Findings @($finding)
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else {
        Write-Host "world-model | query: ${Entity}"
        Write-Host "  risk_posterior: $($ent.risk_posterior)  predicted_next_failure: ${predicted}"
        Write-Host "  coupling: $($ent.coupling -join ', ')"
    }
    exit 0
}

# ── MODE: relations ───────────────────────────────────────────────────────────

if ($Mode -eq 'relations') {
    $model = Get-WorldModel
    $rels  = @($model.relations | Where-Object {
        ($Type -eq '' -or $_.type -eq $Type) -and ([double]$_.strength -ge $MinStrength)
    } | Sort-Object { [double]$_.strength } -Descending)

    [void]$checks.Add([ordered]@{ name = 'relations'; status = 'ok'; detail = "found=$($rels.Count) type=${Type} min=${MinStrength}" })
    $env = New-OsValidatorEnvelope -Tool 'world-model' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Findings @([ordered]@{ count = $rels.Count; relations = @($rels) })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else {
        Write-Host "world-model | relations | type=${Type} min-strength=${MinStrength} | found=$($rels.Count)"
        foreach ($r in $rels) {
            Write-Host "  [$($r.strength)] $($r.from) -> $($r.to) ($($r.type), N=$($r.evidence_count))"
        }
    }
    exit 0
}

# ── MODE: export-context ──────────────────────────────────────────────────────

if ($Mode -eq 'export-context') {
    $model = Get-WorldModel
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('## World Model Context')
    [void]$lines.Add('')

    foreach ($f in $Files) {
        $ent      = Get-OrCreateEntity -Model $model -Key $f
        $risk     = [double]$ent.risk_posterior
        $riskLabel = if ($risk -ge 0.7) { 'HIGH' } elseif ($risk -ge 0.4) { 'MEDIUM' } else { 'LOW' }
        [void]$lines.Add("**${f}** risk=${risk} (${riskLabel}) incidents=$($ent.incident_count)")
        if (@($ent.coupling).Count -gt 0) {
            [void]$lines.Add("  coupling: $($ent.coupling -join ', ')")
        }
        if (@($ent.causal_chain).Count -gt 0) {
            $causes = @($ent.causal_chain | ForEach-Object { $_.cause }) -join ', '
            [void]$lines.Add("  known causes: ${causes}")
        }
    }

    $md = $lines -join "`n"
    [void]$checks.Add([ordered]@{ name = 'export-context'; status = 'ok'; detail = "files=$($Files.Count)" })
    $env = New-OsValidatorEnvelope -Tool 'world-model' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Findings @([ordered]@{ context = $md; files = $Files.Count })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else { Write-Host $md }
    exit 0
}

exit 0
