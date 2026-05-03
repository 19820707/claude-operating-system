# verify-upgrade-notes.ps1 — Contract schemaVersion must be documented in upgrade-manifest.json
#   pwsh ./tools/verify-upgrade-notes.ps1 [-Json] [-Strict]   # -Strict => undocumented bumps fail

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Strict
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

# Keep aligned with tools/verify-json-contracts.ps1 $manifestPairs keys + extras below.
$canonicalWatched = @(
    'agent-adapters-manifest.json',
    'bootstrap-manifest.json',
    'capability-manifest.json',
    'compatibility-manifest.json',
    'component-manifest.json',
    'context-budget.json',
    'deprecation-manifest.json',
    'distribution-manifest.json',
    'docs-index.json',
    'lifecycle-manifest.json',
    'os-capabilities.json',
    'os-manifest.json',
    'playbook-manifest.json',
    'policies/autonomy-policy.json',
    'recipe-manifest.json',
    'runtime-budget.json',
    'script-manifest.json',
    'session-memory-manifest.json',
    'skills-manifest.json',
    'upgrade-manifest.json',
    'workflow-manifest.json'
) | Sort-Object

function Test-WatchedListMatch {
    param([object[]]$Declared)
    $d = @($Declared | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object)
    $c = @($canonicalWatched)
    if ($d.Count -ne $c.Count) {
        return "watchedContractFiles count $($d.Count) != canonical $($c.Count)"
    }
    for ($i = 0; $i -lt $c.Count; $i++) {
        if ($d[$i] -cne $c[$i]) {
            return "watchedContractFiles mismatch at index $i : declared='$($d[$i])' canonical='$($c[$i])'"
        }
    }
    return $null
}

try {
    $umPath = Join-Path $RepoRoot 'upgrade-manifest.json'
    if (-not (Test-Path -LiteralPath $umPath)) {
        throw 'missing upgrade-manifest.json'
    }
    $um = Get-Content -LiteralPath $umPath -Raw | ConvertFrom-Json

    $listErr = Test-WatchedListMatch -Declared @($um.watchedContractFiles)
    if ($listErr) {
        [void]$failures.Add($listErr)
    }

    $maxDoc = @{}
    foreach ($e in @($um.entries)) {
        $eid = if ($e.id) { [string]$e.id } else { '<missing-id>' }

        if ([string]::IsNullOrWhiteSpace([string]$e.versionIntroduced)) {
            [void]$failures.Add("entry '$eid' missing versionIntroduced")
        }
        $sum = [string]$e.summary
        if ($sum.Length -lt 10) { [void]$failures.Add("entry '$eid' summary too short (min 10)") }
        $afs = @($e.affectedFiles | ForEach-Object { [string]$_ })
        if ($afs.Count -lt 1) { [void]$failures.Add("entry '$eid' needs affectedFiles (min 1)") }
        $mig = [string]$e.migrationSteps
        if ($mig.Length -lt 20) { [void]$failures.Add("entry '$eid' migrationSteps too short (min 20)") }
        $rb = [string]$e.rollbackGuidance
        if ($rb.Length -lt 10) { [void]$failures.Add("entry '$eid' rollbackGuidance too short (min 10)") }
        $vc = [string]$e.validationCommand
        if ($vc.Length -lt 10) { [void]$failures.Add("entry '$eid' validationCommand too short (min 10)") }
        elseif ($vc -notmatch '(?i)pwsh|powershell') {
            [void]$failures.Add("entry '$eid' validationCommand should reference pwsh or powershell")
        }

        $bumps = @($e.contractBumps)
        if ($bumps.Count -lt 1) {
            [void]$failures.Add("entry '$eid' needs contractBumps (min 1)")
        }
        foreach ($b in $bumps) {
            $p = ([string]$b.path).Trim() -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($p)) {
                [void]$failures.Add("entry '$eid' has empty contractBump path")
                continue
            }
            if ($canonicalWatched -notcontains $p) {
                [void]$failures.Add("entry '$eid' contractBump unknown path: $p")
                continue
            }
            try {
                $v = [int]$b.schemaVersion
            }
            catch {
                [void]$failures.Add("entry '$eid' contractBump $p has non-integer schemaVersion")
                continue
            }
            if ($v -lt 1) {
                [void]$failures.Add("entry '$eid' contractBump $p invalid schemaVersion")
                continue
            }
            $curM = 0
            if ($maxDoc.ContainsKey($p)) { $curM = [int]$maxDoc[$p] }
            if ($v -gt $curM) { $maxDoc[$p] = $v }
        }
    }

    foreach ($rel in $canonicalWatched) {
        $jp = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $jp)) {
            [void]$failures.Add("watched contract missing on disk: $rel")
            continue
        }
        $j = Get-Content -LiteralPath $jp -Raw | ConvertFrom-Json
        if (-not ($j.PSObject.Properties.Name -contains 'schemaVersion')) {
            [void]$failures.Add("$rel missing root schemaVersion")
            continue
        }
        $cv = [int]$j.schemaVersion
        $doc = if ($maxDoc.ContainsKey($rel)) { [int]$maxDoc[$rel] } else { 0 }
        if ($doc -lt $cv) {
            $msg = "upgrade notes lag $rel : on-disk schemaVersion=$cv max documented=$doc"
            if ($Strict) {
                [void]$failures.Add($msg)
            }
            else {
                [void]$warnings.Add($msg)
            }
            [void]$findings.Add([ordered]@{ path = $rel; onDisk = $cv; documentedMax = $doc })
        }
    }

    [void]$checks.Add([ordered]@{
            name   = 'upgrade-notes-contract-coverage'
            status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
            detail = 'watched root schemaVersion <= max contractBumps across entries'
        })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-upgrade-notes' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-upgrade-notes: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
