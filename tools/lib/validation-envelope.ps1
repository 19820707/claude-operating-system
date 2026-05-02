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
        [ordered]@{
            name      = [string]$c.name
            status    = [string]$c.status
            latencyMs = [int]$c.latency_ms
            detail    = (Redact-SensitiveText -Text ([string]$c.note) -MaxLength 220)
        }
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
