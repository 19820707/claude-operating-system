# verify-lifecycle.ps1 — lifecycle-manifest structure and repo path checks (read-only)
#   pwsh ./tools/verify-lifecycle.ps1
#   pwsh ./tools/verify-lifecycle.ps1 -Json

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

$script:RequiredPhases = [string[]]@(
    'install', 'init', 'update', 'repair', 'rollback', 'uninstall', 'project-bootstrap', 'project-update'
)

$script:MinLens = [ordered]@{
    title                      = 4
    entrypoint                 = 6
    writes                     = 12
    backups                    = 8
    idempotency                = 12
    rollbackBehavior           = 12
    validationAfterExecution   = 12
}

function Test-TrimLen {
    param([string]$Text, [int]$Min, [string]$Ctx)
    $t = if ($null -eq $Text) { '' } else { $Text.Trim() }
    if ($t.Length -lt $Min) { return $false }
    return $true
}

try {
    $path = Join-Path $RepoRoot 'lifecycle-manifest.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'missing lifecycle-manifest.json' }
    $lm = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json

    if (-not $lm.commands -or @($lm.commands).Count -lt 1) {
        throw 'lifecycle-manifest.commands missing or empty'
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $phaseHit = @{}
    foreach ($p in $script:RequiredPhases) { $phaseHit[$p] = $false }

    foreach ($c in @($lm.commands)) {
        $id = [string]$c.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            [void]$failures.Add('command with empty id')
            continue
        }
        if (-not $seen.Add($id)) {
            [void]$failures.Add("duplicate lifecycle command id: $id")
        }

        $ph = [string]$c.phase
        if ($script:RequiredPhases -notcontains $ph) {
            [void]$failures.Add("$id : invalid phase '$ph'")
        }
        else {
            $phaseHit[$ph] = $true
        }

        foreach ($entry in $script:MinLens.GetEnumerator()) {
            $field = [string]$entry.Key
            $min = [int]$entry.Value
            $val = [string]$c.$field
            if (-not (Test-TrimLen -Text $val -Min $min -Ctx "$id.$field")) {
                [void]$failures.Add("$id : field '$field' shorter than $min characters after trim")
            }
        }

        $spProp = $c.PSObject.Properties['scriptPath']
        if ($spProp -and -not [string]::IsNullOrWhiteSpace([string]$spProp.Value)) {
            $rel = [string]$spProp.Value -replace '/', [char][System.IO.Path]::DirectorySeparatorChar
            $full = Join-Path $RepoRoot $rel
            if (-not (Test-Path -LiteralPath $full)) {
                [void]$failures.Add("$id : scriptPath not found: $($spProp.Value)")
                [void]$findings.Add([ordered]@{ id = $id; scriptPath = [string]$spProp.Value; rule = 'missing-path' })
            }
        }
    }

    foreach ($p in $script:RequiredPhases) {
        if (-not $phaseHit[$p]) {
            [void]$failures.Add("no lifecycle command declared for required phase: $p")
        }
    }

    [void]$checks.Add([ordered]@{
            name   = 'lifecycle-contracts'
            status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
            detail = 'lifecycle-manifest commands cover phases; required fields; scriptPath exists when set'
        })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-lifecycle' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "verify-lifecycle: $($env.status)"
    foreach ($f in @($env.failures)) { Write-Host "FAIL: $f" }
    foreach ($w in @($env.warnings)) { Write-Host "WARN: $w" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
