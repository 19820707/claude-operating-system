# decision-audit-engine.ps1 — Audits decision-log.jsonl for policy compliance
# Checks model_selection rules, weak evidence, and scope boundary authorization.
# Always exits 0 (reporter, not blocker).
#   pwsh ./tools/decision-audit-engine.ps1
#   pwsh ./tools/decision-audit-engine.ps1 -Json
#   pwsh ./tools/decision-audit-engine.ps1 -Session 2026-05-16
#   pwsh ./tools/decision-audit-engine.ps1 -Trend

param(
    [switch]$Json,
    [string]$Session = '',
    [switch]$Trend
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$logPath = Join-Path $RepoRoot '.claude/decision-log.jsonl'

# Opus-required trigger patterns (from model-selection policy)
$opusPattern = 'auth|authz|billing|migration|payment|secret|entitlement|publish|incident|sev[0-9]'

# ── Load and parse decision log ───────────────────────────────────────────────
$allRecords = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $logPath) {
    $lines = Get-Content -LiteralPath $logPath -Encoding utf8
    foreach ($line in $lines) {
        $l = $line.Trim()
        if (-not $l) { continue }
        try {
            $r = $l | ConvertFrom-Json
            [void]$allRecords.Add($r)
        } catch { }
    }
    [void]$checks.Add([ordered]@{ name = 'load-log'; status = 'ok'; detail = "$($allRecords.Count) records" })
} else {
    [void]$warnings.Add('decision-log.jsonl not found — no audit data')
    [void]$checks.Add([ordered]@{ name = 'load-log'; status = 'warn'; detail = 'missing' })
}

# ── Group records by session (date prefix of ts) ──────────────────────────────
$bySession = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
foreach ($r in $allRecords) {
    $ts  = if ($r.PSObject.Properties.Name -contains 'ts') { [string]$r.ts } else { 'unknown' }
    $sid = if ($ts.Length -ge 10) { $ts.Substring(0, 10) } else { 'unknown' }
    if (-not $bySession.ContainsKey($sid)) { $bySession[$sid] = [System.Collections.Generic.List[object]]::new() }
    [void]$bySession[$sid].Add($r)
}

# ── Audit function ────────────────────────────────────────────────────────────
function Invoke-SessionAudit {
    param([string]$SessionId, [object[]]$Records)

    $violations    = [System.Collections.Generic.List[object]]::new()
    $weakEvidence  = [System.Collections.Generic.List[object]]::new()
    $total         = 0
    $compliant     = 0

    foreach ($r in $Records) {
        $type = if ($r.PSObject.Properties.Name -contains 'type') { [string]$r.type } else { '' }

        # ── model_selection audit ──────────────────────────────────────────────
        if ($type -eq 'model_selection') {
            $total++
            $trigger    = if ($r.PSObject.Properties.Name -contains 'trigger')    { [string]$r.trigger    } else { '' }
            $model      = if ($r.PSObject.Properties.Name -contains 'model')      { [string]$r.model      } else { '' }
            $confidence = if ($r.PSObject.Properties.Name -contains 'confidence') { [string]$r.confidence } else { '' }
            $evidence   = if ($r.PSObject.Properties.Name -contains 'evidence')   { @($r.evidence)         } else { @() }

            $needsOpus = $trigger -match $opusPattern
            $hasOpus   = $model -match '(?i)opus'

            if ($needsOpus -and -not $hasOpus) {
                [void]$violations.Add([ordered]@{
                    type    = 'model_selection'
                    rule    = 'OPUS_REQUIRED'
                    trigger = $trigger
                    model   = $model
                    ts      = if ($r.PSObject.Properties.Name -contains 'ts') { [string]$r.ts } else { '' }
                })
            } else {
                $compliant++
            }

            if ($confidence -eq 'LOW' -and $evidence.Count -lt 2) {
                [void]$weakEvidence.Add([ordered]@{
                    type    = 'model_selection'
                    rule    = 'WEAK_EVIDENCE'
                    details = "confidence=LOW with $($evidence.Count) evidence item(s)"
                    ts      = if ($r.PSObject.Properties.Name -contains 'ts') { [string]$r.ts } else { '' }
                })
            }
        }

        # ── scope_boundary audit ───────────────────────────────────────────────
        elseif ($type -eq 'scope_boundary') {
            $total++
            $expansion  = if ($r.PSObject.Properties.Name -contains 'scope_expansion') { [bool]$r.scope_expansion } else { $false }
            $authorized = if ($r.PSObject.Properties.Name -contains 'authorized')      { [bool]$r.authorized      } else { $true  }

            if ($expansion -and -not $authorized) {
                [void]$violations.Add([ordered]@{
                    type    = 'scope_boundary'
                    rule    = 'UNAUTHORIZED_EXPANSION'
                    ts      = if ($r.PSObject.Properties.Name -contains 'ts') { [string]$r.ts } else { '' }
                })
            } else {
                $compliant++
            }
        }
    }

    $rate = if ($total -gt 0) { [Math]::Round($compliant / $total, 4) } else { 1.0 }

    return [ordered]@{
        session        = $SessionId
        total          = $total
        compliant      = $compliant
        compliance_rate = $rate
        violations     = @($violations)
        weak_evidence  = @($weakEvidence)
    }
}

# ── Run audits ────────────────────────────────────────────────────────────────
$sessionIds = @($bySession.Keys | Sort-Object)
if ($Session) { $sessionIds = @($sessionIds | Where-Object { $_ -eq $Session }) }

$auditResults = [System.Collections.Generic.List[object]]::new()
foreach ($sid in $sessionIds) {
    $result = Invoke-SessionAudit -SessionId $sid -Records @($bySession[$sid])
    [void]$auditResults.Add($result)
}

# ── Compliance trend ──────────────────────────────────────────────────────────
$currentRate = if ($auditResults.Count -gt 0) { [double]$auditResults[-1].compliance_rate } else { 1.0 }
$last5 = @($auditResults | Select-Object -Last 5)
$avgLast5 = if ($last5.Count -gt 0) {
    ($last5 | ForEach-Object { [double]$_.compliance_rate } | Measure-Object -Average).Average
} else { 1.0 }

$policyDrift = $currentRate -lt ($avgLast5 - 0.05)
$trend = if ($auditResults.Count -lt 2) {
    'stable'
} else {
    $prev = [double]$auditResults[-2].compliance_rate
    $curr = [double]$auditResults[-1].compliance_rate
    if ($curr -gt $prev + 0.02) { 'improving' } elseif ($curr -lt $prev - 0.02) { 'degrading' } else { 'stable' }
}

$totalViolations = ($auditResults | ForEach-Object { $_.violations.Count } | Measure-Object -Sum).Sum
$totalWeak = ($auditResults | ForEach-Object { $_.weak_evidence.Count } | Measure-Object -Sum).Sum

[void]$checks.Add([ordered]@{
    name   = 'compliance'
    status = if ($policyDrift) { 'warn' } else { 'ok' }
    detail = "rate=$([Math]::Round($currentRate,3)) drift=$policyDrift trend=$trend"
})

# ── Output ────────────────────────────────────────────────────────────────────
$sw.Stop()
$st = if ($policyDrift -or $totalViolations -gt 0) { 'warn' } else { 'ok' }

$summary = [ordered]@{
    session         = if ($Session) { $Session } else { if ($sessionIds.Count -gt 0) { $sessionIds[-1] } else { 'all' } }
    compliance_rate = $currentRate
    avg_last5       = [Math]::Round($avgLast5, 4)
    policy_drift    = $policyDrift
    trend           = $trend
    violations      = $totalViolations
    weak_evidence   = $totalWeak
    sessions        = @($auditResults)
}

$env = New-OsValidatorEnvelope -Tool 'decision-audit-engine' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @() `
    -Findings @(@($summary))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'decision-audit-engine'
    if ($Trend) {
        Write-Host "Compliance trend ($($auditResults.Count) sessions):"
        foreach ($a in $auditResults) {
            $bar = '=' * [Math]::Round([double]$a.compliance_rate * 20)
            Write-Host "  $($a.session)  [$bar] $([Math]::Round([double]$a.compliance_rate * 100, 1))%  violations=$($a.violations.Count)"
        }
    } else {
        Write-Host "Compliance rate : $([Math]::Round($currentRate * 100, 1))%  [$trend]"
        Write-Host "Policy drift    : $policyDrift"
        Write-Host "Violations      : $totalViolations"
        Write-Host "Weak evidence   : $totalWeak"
        if ($policyDrift) { Write-Host "WARN: compliance rate dropped below rolling average — policy drift detected" }
    }
}

exit 0
