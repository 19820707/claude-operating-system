# os-autopilot.ps1 — Bounded autonomous orchestration (validate-first; no false-green; no steward writes)
#   pwsh ./tools/os-autopilot.ps1 -Goal "validate docs" -Profile quick -Autonomy A3 -DryRun -Json
# Does not publish releases, mutate production, or bypass validators. Re-runs validation up to -MaxRepairAttempts.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Goal,

    [Parameter(Mandatory = $false)]
    [ValidateSet('quick', 'standard', 'strict')]
    [string]$Profile = 'quick',

    [Parameter(Mandatory = $false)]
    [ValidateSet('A0', 'A1', 'A2', 'A3', 'A4')]
    [string]$Autonomy = 'A3',

    [switch]$DryRun,

    [int]$MaxRepairAttempts = 2,

    [switch]$WriteEvidence,

    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Get-LastJsonObjectFromLines {
    param([string[]]$Lines)
    $line = $Lines | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json) } catch { return $null }
}

function Invoke-PwshLines {
    param([string]$RelativeTool, [string[]]$ArgList)
    $p = Join-Path $RepoRoot $RelativeTool
    return @(& pwsh -NoProfile -File $p @ArgList 2>$null)
}

function Test-GoalEscalation {
    param([string]$Text)
    $t = $Text.ToLowerInvariant()
    $reasons = [System.Collections.Generic.List[string]]::new()
    $critical = $false
    $patterns = @{
        'production'            = 'production'
        'release publish'       = 'release_publish'
        'publish release'       = 'release_publish'
        'deploy prod'           = 'production'
        'migration'             = 'migration'
        'incident'              = 'incident_external_impact'
        'bypass'                = 'validator_bypass'
        'relax policy'          = 'policy_relaxation'
        'secret'                = 'secret_handling'
        'breaking schema'       = 'breaking_schema_change'
        'remove file'           = 'file_removal'
        'delete file'           = 'file_removal'
        'irreversible'          = 'irreversible_action'
        'force push'            = 'destructive_write'
        'git tag'               = 'release_publish'
        'push origin'          = 'release_publish'
    }
    foreach ($k in $patterns.Keys) {
        if ($t.Contains($k)) {
            $critical = $true
            [void]$reasons.Add($patterns[$k])
        }
    }
    if ($t -notmatch 'non-?destructive' -and $t -match '\bdestructive\b') {
        $critical = $true
        [void]$reasons.Add('destructive_write')
    }
    return [ordered]@{ critical = [bool]$critical; reasons = @($reasons | Select-Object -Unique) }
}

function Classify-Risk {
    param([string]$Text, [object]$Escalation)
    if ($Escalation.critical) { return 'critical' }
    $t = $Text.ToLowerInvariant()
    if ($t -match 'strict|security|schema|manifest|adapter|drift') { return 'medium' }
    return 'low'
}

$actionsTaken = [System.Collections.Generic.List[string]]::new()
$actionsSkipped = [System.Collections.Generic.List[string]]::new()
$validations = [System.Collections.Generic.List[object]]::new()
$repairAttempts = [System.Collections.Generic.List[object]]::new()
$evidence = [System.Collections.Generic.List[string]]::new()
$residualRisk = [System.Collections.Generic.List[string]]::new()
$approvalReasons = [System.Collections.Generic.List[string]]::new()

$esc = Test-GoalEscalation -Text $Goal
$risk = Classify-Risk -Text $Goal -Escalation $esc
$requiresApproval = $false
$status = 'ok'

if ($Autonomy -eq 'A4') {
    $requiresApproval = $true
    [void]$approvalReasons.Add('A4 closed-loop autonomy is forbidden by policy')
    $status = 'blocked'
    [void]$actionsSkipped.Add('autonomy_level_A4_blocked')
}

if ($esc.critical) {
    $requiresApproval = $true
    foreach ($r in $esc.reasons) { [void]$approvalReasons.Add($r) }
    if ($status -eq 'ok') { $status = 'blocked' }
    [void]$actionsSkipped.Add('goal_requires_human_approval_surface')
}

if ($DryRun) {
    [void]$actionsSkipped.Add('mutating_writes_skipped_dry_run')
}

# Route / plan (documentation-first; machine-readable)
[void]$actionsTaken.Add('plan:skills:autonomous-runtime,doc-contract-audit,runtime-economy')
[void]$actionsTaken.Add('plan:playbooks:autonomous-repair')
[void]$actionsTaken.Add('plan:validators:verify-autonomy-policy,os-validate')

# verify-autonomy-policy
$apArgs = @('-Json')
if ($Profile -eq 'strict') { $apArgs += '-Strict' }
$apLines = Invoke-PwshLines -RelativeTool 'tools/verify-autonomy-policy.ps1' -ArgList $apArgs
$apExit = [int]$LASTEXITCODE
$apObj = Get-LastJsonObjectFromLines -Lines $apLines
$apSt = if ($apObj) { [string]$apObj.status } else { if ($apExit -eq 0) { 'ok' } else { 'fail' } }
[void]$validations.Add([ordered]@{ name = 'verify-autonomy-policy'; status = $apSt; exitCode = $apExit })
[void]$actionsTaken.Add("run:verify-autonomy-policy exit=$apExit status=$apSt")

if ($apSt -eq 'fail' -or $apExit -ne 0) {
    $status = 'fail'
}
elseif ($apSt -ne 'ok') {
    if ($status -eq 'ok') { $status = 'warn' }
    [void]$residualRisk.Add("verify-autonomy-policy status=$apSt (not treated as passed)")
}

function Invoke-OsValidateOnce {
    param([string]$Prof)
    $lines = Invoke-PwshLines -RelativeTool 'tools/os-validate.ps1' -ArgList @('-Profile', $Prof, '-Json')
    $code = [int]$LASTEXITCODE
    $o = Get-LastJsonObjectFromLines -Lines $lines
    $st = if ($o) { [string]$o.status } else { if ($code -eq 0) { 'ok' } else { 'fail' } }
    return [ordered]@{ exitCode = $code; status = $st; object = $o }
}

if ($status -ne 'blocked' -and $status -ne 'fail') {
    $val = Invoke-OsValidateOnce -Prof $Profile
    [void]$validations.Add([ordered]@{ name = 'os-validate'; status = $val.status; exitCode = $val.exitCode })
    [void]$actionsTaken.Add("run:os-validate -Profile $Profile exit=$($val.exitCode) status=$($val.status)")

    if ($val.status -eq 'fail' -or $val.exitCode -ne 0) {
        $status = 'fail'
    }
    elseif ($val.status -ne 'ok') {
        if ($status -eq 'ok') { $status = 'warn' }
        [void]$residualRisk.Add("os-validate aggregate=$($val.status)")
    }

    $attempt = 0
    while ($attempt -lt $MaxRepairAttempts -and ($val.status -ne 'ok' -or $val.exitCode -ne 0)) {
        $attempt++
        [void]$repairAttempts.Add([ordered]@{ attempt = $attempt; priorStatus = $val.status; priorExit = $val.exitCode; note = 're-run validation only (no mutating repair in autopilot v1)' })
        $val = Invoke-OsValidateOnce -Prof $Profile
        [void]$validations.Add([ordered]@{ name = "os-validate-retry-$attempt"; status = $val.status; exitCode = $val.exitCode })
        if ($val.status -eq 'ok' -and $val.exitCode -eq 0) { break }
    }

    if ($val.status -eq 'fail' -or $val.exitCode -ne 0) {
        $status = 'fail'
    }
    elseif ($val.status -ne 'ok') {
        if ($status -eq 'ok') { $status = 'warn' }
    }
}

# Never downgrade fail to warn
foreach ($v in @($validations)) {
    if ($null -ne $v -and [string]$v.status -eq 'fail') {
        $status = 'fail'
        break
    }
}

# Skipped required validation = fail (never treat skip as pass)
foreach ($v in $validations) {
    if ($v.status -eq 'skip' -and ($v.name -eq 'verify-autonomy-policy' -or $v.name -like 'os-validate*')) {
        $status = 'fail'
        [void]$residualRisk.Add("required validation '$($v.name)' reported skip")
    }
}

if ($WriteEvidence -and $status -ne 'blocked') {
    $sw.Stop()
    $rec = @{
        timestamp  = (Get-Date).ToUniversalTime().ToString('o')
        event      = 'autopilot'
        tool       = 'os-autopilot'
        goal       = $Goal
        profile    = $Profile
        autonomy   = $Autonomy
        status     = $status
        riskLevel  = $risk
        durationMs = [int]$sw.ElapsedMilliseconds
    } | ConvertTo-Json -Compress -Depth 6
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'tools/write-validation-history.ps1')) {
        & (Join-Path $RepoRoot 'tools/write-validation-history.ps1') -Record $rec -RepoRoot $RepoRoot -Quiet
        [void]$evidence.Add('logs/validation-history.jsonl (autopilot record)')
    }
}
else {
    $sw.Stop()
}
$out = [ordered]@{
    tool               = 'os-autopilot'
    goal               = (Redact-SensitiveText -Text $Goal -MaxLength 2000)
    autonomyLevel      = $Autonomy
    riskLevel          = $risk
    status             = $status
    actionsTaken       = @($actionsTaken)
    actionsSkipped     = @($actionsSkipped)
    requiresApproval   = [bool]$requiresApproval
    approvalReasons    = @($approvalReasons)
    validations      = @($validations)
    repairAttempts     = @($repairAttempts)
    evidence           = @($evidence)
    residualRisk       = @($residualRisk)
    durationMs         = [int]$sw.ElapsedMilliseconds
}

if ($Json) {
    $out | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "os-autopilot: $($out.status) risk=$($out.riskLevel) requiresApproval=$($out.requiresApproval)"
}

if ($out.status -in @('fail', 'blocked')) { exit 1 }
if ($out.status -ne 'ok') { exit 1 }
exit 0
