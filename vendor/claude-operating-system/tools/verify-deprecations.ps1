# verify-deprecations.ps1 — deprecation-manifest.json contract + strict surface checks
#   pwsh ./tools/verify-deprecations.ps1 [-Json] [-Strict]
#   -Strict: fail if allowedInStrictMode=false items appear on os-validate / os-validate-all / quality-gates surfaces

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

function Fail {
    param([string]$Message)
    [void]$script:failures.Add($Message)
}

function Test-IsoDate {
    param([string]$Label, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Fail "$Label empty date"
        return $false
    }
    $d = $null
    if (-not [datetime]::TryParse($Value, [ref]$d)) {
        Fail "$Label invalid date: $Value"
        return $false
    }
    return $true
}

function Get-OrchestratorScanPaths {
    param([string]$Root)
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in @(
            'tools/os-validate.ps1',
            'tools/os-validate-all.ps1'
        )) {
        $full = Join-Path $Root ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $full) { [void]$paths.Add($full) }
    }
    $qg = Join-Path $Root 'quality-gates'
    if (Test-Path -LiteralPath $qg) {
        Get-ChildItem -LiteralPath $qg -Filter '*.json' -File | ForEach-Object { [void]$paths.Add($_.FullName) }
    }
    return @($paths)
}

function Test-TextUsesPath {
    param([string]$Text, [string]$NormalizedSlashPath)
    $escaped = [regex]::Escape($NormalizedSlashPath)
    return [regex]::IsMatch($Text, $escaped, 'IgnoreCase')
}

function Get-JoinedManifestScanText {
    param([string]$Root)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in @(
            'skills-manifest.json',
            'os-capabilities.json',
            'capability-manifest.json',
            'bootstrap-manifest.json',
            'docs-index.json',
            'workflow-manifest.json',
            'recipe-manifest.json'
        )) {
        $p = Join-Path $Root ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $p) {
            [void]$parts.Add((Get-Content -LiteralPath $p -Raw -Encoding utf8))
        }
    }
    return ($parts -join "`n")
}

function Get-CommandsListingText {
    param([string]$Root)
    $dir = Join-Path $Root 'templates/commands'
    if (-not (Test-Path -LiteralPath $dir)) { return '' }
    return ((Get-ChildItem -LiteralPath $dir -Filter '*.md' -File | ForEach-Object { $_.Name }) -join "`n")
}

try {
    $mfPath = Join-Path $RepoRoot 'deprecation-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'deprecation-manifest.json missing' }
    $mf = Get-Content -LiteralPath $mfPath -Raw -Encoding utf8 | ConvertFrom-Json

    $seen = @{}
    $orchestratorText = @((Get-OrchestratorScanPaths -Root $RepoRoot | ForEach-Object {
                Get-Content -LiteralPath $_ -Raw -Encoding utf8
            })) -join "`n"
    $manifestBlob = Get-JoinedManifestScanText -Root $RepoRoot
    $indexPath = Join-Path $RepoRoot 'INDEX.md'
    $indexText = if (Test-Path -LiteralPath $indexPath) { Get-Content -LiteralPath $indexPath -Raw -Encoding utf8 } else { '' }
    $docsIndexPath = Join-Path $RepoRoot 'docs-index.json'
    $docsIndexText = if (Test-Path -LiteralPath $docsIndexPath) { Get-Content -LiteralPath $docsIndexPath -Raw -Encoding utf8 } else { '' }
    $docBlob = "$manifestBlob`n$indexText`n$docsIndexText"
    $commandListing = Get-CommandsListingText -Root $RepoRoot

    function Register-Id {
        param([string]$Id)
        if ($seen.ContainsKey($Id)) { Fail "duplicate deprecation id: $Id" }
        $seen[$Id] = $true
    }

    function Test-Entry {
        param($Entry, [string]$Category)
        $id = [string]$Entry.id
        if ([string]::IsNullOrWhiteSpace($id)) { Fail "$Category entry missing id"; return }
        Register-Id -Id $id
        foreach ($prop in @('target', 'replacement', 'reason', 'migrationInstructions')) {
            if (-not ($Entry.PSObject.Properties.Name -contains $prop) -or [string]::IsNullOrWhiteSpace([string]$Entry.$prop)) {
                Fail "$id missing $prop"
            }
        }
        if (-not ($Entry.PSObject.Properties.Name -contains 'allowedInStrictMode')) { Fail "$id missing allowedInStrictMode" }
        $null = [bool]$Entry.allowedInStrictMode

        $ds = [string]$Entry.deprecatedSince
        $rb = [string]$Entry.removalNotBefore
        if (-not (Test-IsoDate -Label "$id.deprecatedSince" -Value $ds)) { return }
        if (-not (Test-IsoDate -Label "$id.removalNotBefore" -Value $rb)) { return }
        $d1 = [datetime]::Parse($ds)
        $d2 = [datetime]::Parse($rb)
        if ($d2 -lt $d1) { Fail "$id removalNotBefore before deprecatedSince" }
    }

    foreach ($e in @($mf.deprecatedScripts | ForEach-Object { $_ })) { Test-Entry -Entry $e -Category 'deprecatedScripts' }
    foreach ($e in @($mf.deprecatedSkills | ForEach-Object { $_ })) { Test-Entry -Entry $e -Category 'deprecatedSkills' }
    foreach ($e in @($mf.deprecatedDocs | ForEach-Object { $_ })) { Test-Entry -Entry $e -Category 'deprecatedDocs' }
    foreach ($e in @($mf.deprecatedCommands | ForEach-Object { $_ })) { Test-Entry -Entry $e -Category 'deprecatedCommands' }

    foreach ($e in @($mf.deprecatedManifestFields | ForEach-Object { $_ })) {
        Register-Id -Id ([string]$e.id)
        foreach ($prop in @('manifestPath', 'jsonKey', 'replacement', 'reason', 'migrationInstructions')) {
            if (-not ($e.PSObject.Properties.Name -contains $prop) -or [string]::IsNullOrWhiteSpace([string]$e.$prop)) {
                Fail "$($e.id) missing $prop"
            }
        }
        if (-not ($e.PSObject.Properties.Name -contains 'allowedInStrictMode')) { Fail "$($e.id) missing allowedInStrictMode" }
        $null = [bool]$e.allowedInStrictMode
        if (-not (Test-IsoDate -Label "$($e.id).deprecatedSince" -Value ([string]$e.deprecatedSince))) { continue }
        if (-not (Test-IsoDate -Label "$($e.id).removalNotBefore" -Value ([string]$e.removalNotBefore))) { continue }
        $md1 = [datetime]::Parse([string]$e.deprecatedSince)
        $md2 = [datetime]::Parse([string]$e.removalNotBefore)
        if ($md2 -lt $md1) { Fail "$($e.id) removalNotBefore before deprecatedSince" }
        $mp = Join-Path $RepoRoot ([string]$e.manifestPath -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $mp)) { Fail "$($e.id) manifestPath missing: $($e.manifestPath)" }
        else {
            $raw = Get-Content -LiteralPath $mp -Raw -Encoding utf8
            $key = [string]$e.jsonKey
            if ($raw -match [regex]::Escape($key)) {
                $msg = "deprecated manifest field still present: $($e.manifestPath) :: $key ($($e.id))"
                if (-not [bool]$e.allowedInStrictMode) {
                    if ($Strict) { Fail $msg }
                    else { [void]$warnings.Add($msg) }
                }
            }
        }
    }

    foreach ($e in @($mf.deprecatedScripts | ForEach-Object { $_ })) {
        $target = ([string]$e.target) -replace '\\', '/'
        if ($target -notmatch '^tools/[A-Za-z0-9._-]+\.ps1$') { Fail "$($e.id) invalid script target: $target"; continue }
        if (Test-TextUsesPath -Text $orchestratorText -NormalizedSlashPath $target) {
            $msg = "deprecated script '$target' referenced on orchestrator/release gate surface ($($e.id))"
            if (-not [bool]$e.allowedInStrictMode) {
                if ($Strict) { Fail $msg }
                else { [void]$warnings.Add($msg) }
            }
        }
        [void]$findings.Add([ordered]@{ kind = 'script'; id = $e.id; target = $target })
    }

    foreach ($e in @($mf.deprecatedSkills | ForEach-Object { $_ })) {
        $tid = [string]$e.target
        $needle = "source/skills/$tid"
        $hitSkill = (Test-TextUsesPath -Text $manifestBlob -NormalizedSlashPath $needle) -or (Test-TextUsesPath -Text $docBlob -NormalizedSlashPath $tid)
        if ($hitSkill) {
            $msg = "deprecated skill '$tid' still referenced ($($e.id))"
            if (-not [bool]$e.allowedInStrictMode) {
                if ($Strict) { Fail $msg }
                else { [void]$warnings.Add($msg) }
            }
        }
        [void]$findings.Add([ordered]@{ kind = 'skill'; id = $e.id; target = $tid })
    }

    foreach ($e in @($mf.deprecatedDocs | ForEach-Object { $_ })) {
        $tp = ([string]$e.target) -replace '\\', '/'
        if (Test-TextUsesPath -Text $docBlob -NormalizedSlashPath $tp) {
            $msg = "deprecated doc path '$tp' still referenced ($($e.id))"
            if (-not [bool]$e.allowedInStrictMode) {
                if ($Strict) { Fail $msg }
                else { [void]$warnings.Add($msg) }
            }
        }
        [void]$findings.Add([ordered]@{ kind = 'doc'; id = $e.id; target = $tp })
    }

    foreach ($e in @($mf.deprecatedCommands | ForEach-Object { $_ })) {
        $cmd = [string]$e.target
        if ($commandListing -and ($commandListing -match "(?m)^$([regex]::Escape($cmd))$")) {
            $msg = "deprecated command '$cmd' still present under templates/commands ($($e.id))"
            if (-not [bool]$e.allowedInStrictMode) {
                if ($Strict) { Fail $msg }
                else { [void]$warnings.Add($msg) }
            }
        }
        [void]$findings.Add([ordered]@{ kind = 'command'; id = $e.id; target = $cmd })
    }

    [void]$checks.Add([ordered]@{ name = 'deprecation-manifest'; status = 'ok'; detail = 'structure + surface scan' })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-deprecations' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "verify-deprecations: $($env.status)$(if ($Strict) { ' (strict surfaces)' })"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
