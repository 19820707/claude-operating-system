# verify-compatibility.ps1 — compatibility-manifest vs script-manifest validators (read-only)
#   pwsh ./tools/verify-compatibility.ps1
#   pwsh ./tools/verify-compatibility.ps1 -Json

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

$script:ExtraValidatorIds = [string[]]@(
    'append-approval-log',
    'autonomous-commit-gate',
    'classify-change',
    'test-skills',
    'run-contract-tests',
    'evaluate-quality-gate',
    'os-doctor',
    'os-autopilot',
    'os-validate',
    'os-validate-all',
    'sync-generated-targets'
)

function Get-ExpectedValidatorIds {
    param([object]$Manifest)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @($Manifest.tools)) {
        $p = [string]$t.path
        if ($p -match '(?i)^tools/verify-.+\.ps1$') {
            [void]$set.Add([string]$t.id)
        }
        elseif ($script:ExtraValidatorIds -contains [string]$t.id) {
            [void]$set.Add([string]$t.id)
        }
    }
    return @($set | Sort-Object)
}

function Merge-SupportRow {
    param([string[]]$Keys, [hashtable]$Defaults, [object]$Overrides)
    $row = [ordered]@{}
    foreach ($k in $Keys) {
        $row[$k] = [string]$Defaults[$k]
    }
    if ($null -ne $Overrides -and $Overrides.PSObject) {
        foreach ($p in $Overrides.PSObject.Properties) {
            $row[[string]$p.Name] = [string]$p.Value
        }
    }
    return $row
}

try {
    $smPath = Join-Path $RepoRoot 'script-manifest.json'
    $cmPath = Join-Path $RepoRoot 'compatibility-manifest.json'
    if (-not (Test-Path -LiteralPath $smPath)) { throw 'missing script-manifest.json' }
    if (-not (Test-Path -LiteralPath $cmPath)) { throw 'missing compatibility-manifest.json' }

    $sm = Get-Content -LiteralPath $smPath -Raw -Encoding utf8 | ConvertFrom-Json
    $cm = Get-Content -LiteralPath $cmPath -Raw -Encoding utf8 | ConvertFrom-Json

    $expected = Get-ExpectedValidatorIds -Manifest $sm
    $idsRaw = @($cm.validators | ForEach-Object { [string]$_.id })
    foreach ($g in ($idsRaw | Group-Object)) {
        if ($g.Count -gt 1) {
            [void]$failures.Add("duplicate compatibility validator row for id: $($g.Name)")
        }
    }
    $declared = @($idsRaw | Sort-Object -Unique)

    foreach ($id in $expected) {
        if ($id -notin $declared) {
            [void]$failures.Add("compatibility-manifest missing validator: $id")
            [void]$findings.Add([ordered]@{ rule = 'missing-declaration'; id = $id })
        }
    }
    foreach ($id in $declared) {
        if ($id -notin $expected) {
            [void]$failures.Add("compatibility-manifest has unknown validator id (not in script-manifest rule): $id")
            [void]$findings.Add([ordered]@{ rule = 'unknown-validator'; id = $id })
        }
    }

    $platKeys = @(
        'win-ps-5.1', 'win-pwsh', 'linux-pwsh', 'macos-pwsh',
        'bash-on-path', 'git-bash', 'wsl', 'gha-ubuntu', 'gha-windows'
    )

    $def = @{}
    foreach ($k in $platKeys) {
        $pv = $cm.defaultSupport.PSObject.Properties[$k]
        if (-not $pv) {
            [void]$failures.Add("defaultSupport missing key: $k")
            $def[$k] = 'unsupported'
            continue
        }
        $def[$k] = [string]$pv.Value
    }

    $catalogIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in @($cm.platformCatalog)) {
        [void]$catalogIds.Add([string]$row.id)
    }
    foreach ($pk in $platKeys) {
        if (-not $catalogIds.Contains($pk)) {
            [void]$failures.Add("platformCatalog missing id: $pk")
        }
    }
    foreach ($cid in $catalogIds) {
        if ($cid -notin $platKeys) {
            [void]$failures.Add("platformCatalog has unknown id: $cid")
        }
    }

    $toolById = @{}
    foreach ($t in @($sm.tools)) { $toolById[[string]$t.id] = $t }

    foreach ($v in @($cm.validators)) {
        $id = [string]$v.id
        if (-not $toolById.ContainsKey($id)) {
            [void]$failures.Add("validator id not found in script-manifest tools: $id")
            continue
        }
        $ov = $v.PSObject.Properties['overrides']
        $merged = Merge-SupportRow -Keys $platKeys -Defaults $def -Overrides $(if ($ov) { $v.overrides } else { $null })
        foreach ($pk in $platKeys) {
            if (-not ($merged.Keys -ccontains $pk)) {
                [void]$failures.Add("$id : missing merged platform $pk")
                continue
            }
            $val = [string]$merged[$pk]
            if ($val -notin @('supported', 'best-effort', 'not-applicable', 'unsupported')) {
                [void]$failures.Add("$id : invalid support level for $pk : $val")
            }
        }
        if ($ov -and $v.overrides) {
            foreach ($p in $v.overrides.PSObject.Properties) {
                $kn = [string]$p.Name
                if ($kn -notin $platKeys) {
                    [void]$failures.Add("$id : overrides has unknown key: $kn")
                }
            }
        }
    }

    [void]$checks.Add([ordered]@{
            name   = 'compatibility-matrix'
            status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
            detail = 'compatibility-manifest validators match script-manifest; platform rows complete'
        })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-compatibility' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "verify-compatibility: $($env.status)"
    foreach ($f in @($env.failures)) { Write-Host "FAIL: $f" }
    foreach ($w in @($env.warnings)) { Write-Host "WARN: $w" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
