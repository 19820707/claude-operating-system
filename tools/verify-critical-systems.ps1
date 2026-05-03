# verify-critical-systems.ps1 — Senior/critical-systems policy verifier
#   pwsh ./tools/verify-critical-systems.ps1
#   pwsh ./tools/verify-critical-systems.ps1 -Json

param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
$script:Records = [System.Collections.Generic.List[object]]::new()
$script:Fails = [System.Collections.Generic.List[string]]::new()

function Invoke-Check {
    param([string]$Name, [string]$ScriptName)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # Hashtable splat — array splat of '-Json' can bind positionally and break child scripts.
        $childArgs = @{}
        if ($Json) { $childArgs['Json'] = $true }
        & (Join-Path $RepoRoot "tools/$ScriptName") @childArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$ScriptName returned non-zero" }
        $sw.Stop()
        [void]$script:Records.Add([pscustomobject]@{ name = $Name; status = 'ok'; latencyMs = [int]$sw.ElapsedMilliseconds; detail = '' })
    } catch {
        $sw.Stop()
        $msg = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 260
        [void]$script:Fails.Add($Name)
        [void]$script:Records.Add([pscustomobject]@{ name = $Name; status = 'fail'; latencyMs = [int]$sw.ElapsedMilliseconds; detail = $msg })
        if (-not $Json) { Write-Host "FAIL: $Name - $msg" }
    }
}

if (-not $Json) {
    Write-Host 'verify-critical-systems'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
}

Invoke-Check -Name 'token-economy-policy' -ScriptName 'verify-token-economy-policy.ps1'
Invoke-Check -Name 'security-policy' -ScriptName 'verify-security-policy.ps1'
Invoke-Check -Name 'claudeignore-scope-control' -ScriptName 'verify-claudeignore.ps1'
Invoke-Check -Name 'agent-adapters' -ScriptName 'verify-agent-adapters.ps1'

$status = if ($script:Fails.Count -gt 0) { 'fail' } else { 'ok' }
$out = [ordered]@{
    name = 'verify-critical-systems'
    status = $status
    failures = @($script:Fails)
    checks = @($script:Records)
    repoRoot = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
}

if ($Json) {
    $out | ConvertTo-Json -Depth 8 -Compress | Write-Output
} elseif ($script:Fails.Count -eq 0) {
    foreach ($r in $script:Records) { Write-Host "OK: $($r.name) ($($r.latencyMs) ms)" }
    Write-Host 'Critical-systems policy checks passed.'
}

if ($script:Fails.Count -gt 0) {
    throw "Critical-systems verification failed: $($script:Fails.Count) issue(s)."
}
