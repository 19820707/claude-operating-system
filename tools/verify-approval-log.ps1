# verify-approval-log.ps1 — Steward playbooks document the ledger; optional JSONL structural validation
#   pwsh ./tools/verify-approval-log.ps1 [-Json]
# Does not require approvals for normal local validation; never requires logs/approval-log.jsonl to exist.

[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

$stewardTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($t in @('Release', 'Production', 'Critical', 'Incident', 'Migration', 'Destructive')) { [void]$stewardTags.Add($t) }

function Test-ApprovalLogLine {
    param([object]$o, [int]$LineNo)
    $pfx = "approval-log.jsonl line $LineNo"
    if (-not $o) {
        return "$pfx : invalid JSON"
    }
    $req = @(
        'timestamp', 'operation', 'riskLevel', 'approver', 'scope',
        'commandOrActionApproved', 'expirationOrUse', 'relatedValidationEvidence', 'rollbackPlanReference'
    )
    foreach ($k in $req) {
        if (-not ($o.PSObject.Properties.Name -contains $k)) {
            return "$pfx : missing property $k"
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$o.timestamp)) { return "$pfx : empty timestamp" }
    if ([string]::IsNullOrWhiteSpace([string]$o.operation)) { return "$pfx : empty operation" }
    $rl = [string]$o.riskLevel
    if ($rl -notin @('low', 'medium', 'high', 'critical')) { return "$pfx : invalid riskLevel" }
    if ([string]::IsNullOrWhiteSpace([string]$o.approver)) { return "$pfx : empty approver" }
    if ([string]::IsNullOrWhiteSpace([string]$o.scope)) { return "$pfx : empty scope" }
    if ([string]::IsNullOrWhiteSpace([string]$o.commandOrActionApproved)) { return "$pfx : empty commandOrActionApproved" }

    $ex = $o.expirationOrUse
    if (-not $ex) { return "$pfx : expirationOrUse missing" }
    $hasExp = $ex.PSObject.Properties.Name -contains 'expiresAt' -and -not [string]::IsNullOrWhiteSpace([string]$ex.expiresAt)
    $otu = $false
    if ($ex.PSObject.Properties.Name -contains 'oneTimeUse') {
        try { $otu = [bool]$ex.oneTimeUse } catch { $otu = $false }
    }
    if (-not $hasExp -and -not $otu) {
        return "$pfx : expirationOrUse must include expiresAt or oneTimeUse true"
    }

    $rel = $o.relatedValidationEvidence
    $arr = @($rel)
    if ($arr.Count -lt 1) { return "$pfx : relatedValidationEvidence must be non-empty array" }
    foreach ($x in $arr) {
        if ([string]::IsNullOrWhiteSpace([string]$x)) { return "$pfx : relatedValidationEvidence contains empty item" }
    }
    if ([string]::IsNullOrWhiteSpace([string]$o.rollbackPlanReference)) {
        return "$pfx : empty rollbackPlanReference"
    }
    return $null
}

try {
    $mfPath = Join-Path $RepoRoot 'playbook-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing playbook-manifest.json' }
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    foreach ($pb in @($mf.playbooks)) {
        $id = [string]$pb.id
        $tags = @($pb.requiresApprovalFor | ForEach-Object { [string]$_ })
        $hit = @($tags | Where-Object { $stewardTags.Contains($_) })
        if ($hit.Count -eq 0) { continue }

        $rel = [string]$pb.path
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            [void]$failures.Add("playbook $id missing file: $rel")
            continue
        }
        $body = Get-Content -LiteralPath $full -Raw
        if ($body -notmatch '(?m)^##\s+Approval ledger\s*$') {
            [void]$failures.Add("playbook $id declares steward tags ($($hit -join ', ')) but missing '## Approval ledger' section ($rel)")
            continue
        }
        foreach ($pair in @(
                @{ n = 'append-approval-log.ps1'; p = 'append-approval-log' }
                @{ n = 'verify-approval-log.ps1'; p = 'verify-approval-log' }
                @{ n = 'docs/APPROVALS.md'; p = 'APPROVALS' }
                @{ n = 'schemas/approval-log.schema.json'; p = 'approval-log.schema' }
                @{ n = 'logs/approval-log.jsonl'; p = 'approval-log.jsonl' }
            )) {
            if ($body -notmatch [regex]::Escape($pair.p)) {
                [void]$failures.Add("playbook $id Approval ledger must reference $($pair.n) ($rel)")
            }
        }
        [void]$findings.Add([ordered]@{ playbookId = $id; stewardTags = @($hit); path = $rel })
    }

    $logPath = Join-Path $RepoRoot 'logs/approval-log.jsonl'
    if (Test-Path -LiteralPath $logPath) {
        $raw = Get-Content -LiteralPath $logPath -Encoding utf8
        $ln = 0
        foreach ($line in $raw) {
            $ln++
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            try {
                $o = $t | ConvertFrom-Json
            }
            catch {
                [void]$failures.Add("approval-log.jsonl line $ln : JSON parse error")
                continue
            }
            $err = Test-ApprovalLogLine -o $o -LineNo $ln
            if ($err) { [void]$failures.Add($err) }
        }
        [void]$checks.Add([ordered]@{ name = 'ledger-jsonl'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'logs/approval-log.jsonl present' })
    }
    else {
        [void]$checks.Add([ordered]@{ name = 'ledger-jsonl'; status = 'ok'; detail = 'logs/approval-log.jsonl absent (optional)' })
    }

    [void]$checks.Add([ordered]@{
            name   = 'playbook-ledger-docs'
            status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' })
            detail = 'steward-tagged playbooks reference approval ledger'
        })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-approval-log' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-approval-log: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
