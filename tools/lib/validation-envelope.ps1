# validation-envelope.ps1 — Shared machine-readable summaries for OS verifiers (dot-source only)
# Requires: Redact-SensitiveText from safe-output.ps1

function New-OsHealthEnvelope {
    param(
        [bool]$Strict,
        [object[]]$Checks,
        [int]$FailureCount,
        [int]$WarningCount,
        [string]$RepoRoot,
        [int]$TotalLatencyMs
    )
    $status = if ($FailureCount -gt 0) {
        'fail'
    } elseif ($WarningCount -gt 0) {
        'warn'
    } else {
        'ok'
    }
    $checkObjs = foreach ($c in $Checks) {
        $row = [ordered]@{
            name      = [string]$c.name
            status    = [string]$c.status
            latencyMs = [int]$c.latency_ms
            detail    = (Redact-SensitiveText -Text ([string]$c.note) -MaxLength 220)
        }
        if ([string]$c.status -in @('warn', 'fail', 'skip')) {
            foreach ($k in @('reason', 'impact', 'remediation', 'strictImpact', 'docsLink')) {
                $pv = $c.PSObject.Properties[$k]
                $raw = if ($pv) { [string]$pv.Value } else { '' }
                $row[$k] = (Redact-SensitiveText -Text $raw -MaxLength 400)
            }
        }
        $row
    }
    return [ordered]@{
        name     = 'verify-os-health'
        status   = $status
        strict   = [bool]$Strict
        checks   = @($checkObjs)
        warnings = $WarningCount
        failures = $FailureCount
        totalMs  = $TotalLatencyMs
        repo     = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
    }
}

function New-OsValidatorEnvelope {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][ValidateSet('ok', 'warn', 'fail', 'skip', 'blocked', 'degraded', 'unknown', 'not_run')][string]$Status,
        [int]$DurationMs = 0,
        [object[]]$Checks = @(),
        [string[]]$Warnings = @(),
        [string[]]$Failures = @(),
        [object[]]$Findings = @(),
        [string[]]$Actions = @()
    )
    $w = @($Warnings | ForEach-Object { Redact-SensitiveText -Text ([string]$_) -MaxLength 400 })
    $f = @($Failures | ForEach-Object { Redact-SensitiveText -Text ([string]$_) -MaxLength 400 })
    return [ordered]@{
        tool      = [string]$Tool
        status    = [string]$Status
        durationMs = [int]$DurationMs
        checks    = @($Checks)
        warnings  = @($w)
        failures  = @($f)
        findings  = @($Findings)
        actions   = @($Actions)
    }
}
