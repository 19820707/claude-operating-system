# classify-change.ps1 — Map (path, operationType, riskSurface) → autonomous / approval / validation (audit-friendly)
#   pwsh ./tools/classify-change.ps1 -Path policies/foo.md -OperationType read -RiskSurface none [-Json]
#   pwsh ./tools/classify-change.ps1 -SelfTest   # built-in cases; exit 1 on mismatch

[CmdletBinding()]
param(
    [string]$Path = '.',
    [string]$OperationType = 'read',
    [string]$RiskSurface = 'none',
    [switch]$Json,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')

function Get-AutonomyPolicy {
    $p = Join-Path $RepoRoot 'policies/autonomy-policy.json'
    if (-not (Test-Path -LiteralPath $p)) { throw 'missing policies/autonomy-policy.json' }
    return Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
}

function Normalize-Op {
    param([string]$Op)
    $o = ($Op -replace '[-\s]', '_').ToLowerInvariant()
    switch ($o) {
        'gitstatus' { return 'git_status' }
        'gitdiff' { return 'git_diff' }
        default { return $o }
    }
}

function Invoke-Classification {
    param(
        [string]$PathIn,
        [string]$OpIn,
        [string]$RiskIn
    )
    $policy = Get-AutonomyPolicy
    $steward = @($policy.requiresHumanApproval.surfaces | ForEach-Object { [string]$_ })
    $risk = ($RiskIn -replace '\s', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($risk) -or $risk -eq 'none') { $risk = 'none' }

    $op = Normalize-Op -Op $OpIn
    $readLike = @('read', 'list', 'search', 'inspect', 'analyze', 'report', 'plan', 'dry-run', 'diff', 'git_status', 'git_diff', 'status')
    $validateLike = @('typecheck', 'test', 'lint', 'validate', 'format_docs')
    $writeLike = @('write', 'patch', 'edit', 'repair', 'update', 'delete', 'remove', 'migrate', 'deploy', 'publish', 'release')

    $onSteward = ($risk -ne 'none') -and ($steward -contains $risk)

    if ($onSteward -and ($writeLike -contains $op -or $op -match '^(promote|relax|bypass|force)')) {
        return [ordered]@{
            autonomous         = $false
            requiresApproval   = $true
            reason               = "Operation '$op' on steward risk surface '$risk' requires human approval per policies/autonomy-policy.json."
            requiredValidation   = @('strict')
            autonomyLevelHint    = 'A1'
        }
    }

    if ($onSteward -and ($readLike -contains $op -or $validateLike -contains $op)) {
        return [ordered]@{
            autonomous         = $true
            requiresApproval   = $false
            reason               = "Read-like or validation signal on steward surface '$risk' has no state-changing blast radius when confined to analysis commands."
            requiredValidation   = @('none')
            autonomyLevelHint    = 'A3'
        }
    }

    if ($readLike -contains $op -or $validateLike -contains $op) {
        return [ordered]@{
            autonomous         = $true
            requiresApproval   = $false
            reason               = 'Read-only or standard validation command; align with policies/auto-approve-matrix.md for local autonomy.'
            requiredValidation   = @($(if ($validateLike -contains $op) { 'standard' } else { 'none' }))
            autonomyLevelHint    = 'A3'
        }
    }

    if ($writeLike -contains $op) {
        return [ordered]@{
            autonomous         = $true
            requiresApproval   = $false
            reason               = "Write-class operation '$op' treated as reversible local engineering; steward must still run validation before merge."
            requiredValidation   = @('standard')
            autonomyLevelHint    = 'A3'
        }
    }

    return [ordered]@{
        autonomous         = $false
        requiresApproval   = $true
        reason               = "Unclassified operation '$op' — default conservative until mapped in policies or playbooks."
        requiredValidation   = @('standard')
        autonomyLevelHint    = 'A1'
    }
}

if ($SelfTest) {
    $cases = @(
        @{ path = 'src/app.ts'; op = 'read'; risk = 'migration'; expectAutonomous = $true; expectApproval = $false }
        @{ path = 'supabase/migrations/x.sql'; op = 'write'; risk = 'migration'; expectAutonomous = $false; expectApproval = $true }
        @{ path = 'README.md'; op = 'typecheck'; risk = 'none'; expectAutonomous = $true; expectApproval = $false }
        @{ path = 'tools/x.ps1'; op = 'publish'; risk = 'release_publish'; expectAutonomous = $false; expectApproval = $true }
    )
    $bad = 0
    foreach ($t in $cases) {
        $r = Invoke-Classification -PathIn $t.path -OpIn $t.op -RiskIn $t.risk
        if ([bool]$r.autonomous -ne $t.expectAutonomous -or [bool]$r.requiresApproval -ne $t.expectApproval) {
            Write-Host "SELFTEST FAIL: $($t.op) $($t.risk) autonomous=$($r.autonomous) approval=$($r.requiresApproval)"
            $bad++
        }
    }
    if ($bad -gt 0) { exit 1 }
    Write-Host 'classify-change: SelfTest ok'
    exit 0
}

$out = Invoke-Classification -PathIn $Path -OpIn $OperationType -RiskIn $RiskSurface
$out['path'] = (Redact-SensitiveText -Text $Path -MaxLength 200)
$out['operationType'] = $OperationType
$out['riskSurface'] = $RiskSurface

if ($Json) {
    $out | ConvertTo-Json -Depth 6 -Compress | Write-Output
}
else {
    Write-Host "autonomous=$($out.autonomous) requiresApproval=$($out.requiresApproval)"
    Write-Host "reason: $($out.reason)"
    Write-Host "requiredValidation: $($out.requiredValidation -join ', ')"
}
exit 0
