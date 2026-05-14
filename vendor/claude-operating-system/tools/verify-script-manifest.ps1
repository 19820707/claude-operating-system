# verify-script-manifest.ps1 — script-manifest.json vs tools/**/*.ps1 and bootstrap shell count
#   pwsh ./tools/verify-script-manifest.ps1 [-Json] [-Strict]   # -Strict => fail high writeRisk tools without dry-run/WhatIf family

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')
. (Join-Path $RepoRoot 'tools/lib/safe-apply.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

try {
    $mfPath = Join-Path $RepoRoot 'script-manifest.json'
    $schemaPath = Join-Path $RepoRoot 'schemas/script-manifest.schema.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing script-manifest.json' }
    $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    $listed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @($mf.tools)) {
        $p = [string]$t.path
        [void]$listed.Add($p)
        $full = Join-Path $RepoRoot $p
        if (-not (Test-Path -LiteralPath $full)) {
            [void]$failures.Add("script-manifest lists missing file: $p")
        }
        if ([string]$t.maturity -eq 'deprecated') {
            [void]$warnings.Add("deprecated tool listed: $p")
        }
        if ([string]$t.maturity -eq 'deprecated' -and $t.defaultEnabled -eq $true) {
            [void]$failures.Add("deprecated tool must not have defaultEnabled true: $p")
        }
        if ([string]$t.maturity -eq 'experimental' -and $t.defaultEnabled -eq $true -and $t.safeToRunInCI -eq $true) {
            [void]$warnings.Add("experimental + defaultEnabled + safeToRunInCI for $p — review before strict CI")
        }
    }

    foreach ($t in @($mf.tools)) {
        $p = [string]$t.path
        if ($p -notmatch '(?i)^tools/.+\.ps1$') { continue }
        $nn = @( @($t.writes | ForEach-Object { [string]$_ }) | Where-Object { $_ -match '\S' } )
        $writesDeclared = $nn.Count -gt 0
        $risk = [string]$t.writeRisk
        if (-not $risk) { $risk = if ($writesDeclared) { 'medium' } else { 'none' } }
        if (-not $writesDeclared -and $risk -ne 'high') { continue }

        $full = Join-Path $RepoRoot $p
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
        $sig = Get-SafeApplySignalsFromScriptText -Raw $raw
        $ok = Test-SafeApplyDryRunFamily -Signals $sig
        $tid = [string]$t.id
        if ($writesDeclared -and -not $ok) {
            [void]$warnings.Add("safe-apply: $tid declares writes[] but lacks -DryRun/-WhatIf or CmdletBinding(SupportsShouldProcess): $p")
        }
        if ($Strict -and $risk -eq 'high' -and -not $ok) {
            [void]$failures.Add("safe-apply strict: writeRisk=high without dry-run/WhatIf family: $tid ($p)")
        }
        [void]$findings.Add([ordered]@{
                toolId        = $tid
                path          = $p
                writeRisk     = $risk
                dryRunFamily  = $ok
                writesDeclared = $writesDeclared
            })
    }

    if ($mf.PSObject.Properties.Name -contains 'shellScripts') {
        $shListed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($t in @($mf.shellScripts)) {
            $p = [string]$t.path
            [void]$shListed.Add($p)
            $full = Join-Path $RepoRoot $p
            if (-not (Test-Path -LiteralPath $full)) {
                [void]$failures.Add("script-manifest shellScripts lists missing file: $p")
            }
            if ([string]$t.maturity -eq 'deprecated' -and $t.defaultEnabled -eq $true) {
                [void]$failures.Add("deprecated shell script must not have defaultEnabled true: $p")
            }
            if ([string]$t.maturity -eq 'experimental' -and $t.defaultEnabled -eq $true -and $t.safeToRunInCI -eq $true) {
                [void]$warnings.Add("experimental shell + defaultEnabled + safeToRunInCI for $p — review before strict CI")
            }
        }
        $shDisk = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'templates/scripts') -Filter *.sh -File -ErrorAction SilentlyContinue | ForEach-Object {
            $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        }
        foreach ($d in $shDisk) {
            if (-not $shListed.Contains($d)) {
                [void]$failures.Add("templates/scripts shell file not listed in script-manifest.shellScripts: $d")
            }
        }
    }
    else {
        [void]$warnings.Add('script-manifest.json missing shellScripts[] — add maturity metadata for templates/scripts/*.sh')
    }

    $disk = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tools') -Recurse -Filter *.ps1 -File | ForEach-Object {
        $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
    }
    foreach ($d in $disk) {
        if ($d -match '(?i)^tools/lib/') { continue }
        if (-not $listed.Contains($d)) {
            [void]$failures.Add("tools script not listed in script-manifest.json: $d")
        }
    }

    $bm = Get-Content -LiteralPath (Join-Path $RepoRoot 'bootstrap-manifest.json') -Raw | ConvertFrom-Json
    $tsProp = $bm.repoIntegrity.PSObject.Properties['templates/scripts']
    if (-not $tsProp) { throw 'bootstrap-manifest missing repoIntegrity.templates/scripts' }
    $expectedSh = [int]$tsProp.Value.exact
    $shCount = (Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'templates/scripts') -Filter *.sh -File).Count
    if ($shCount -ne $expectedSh) {
        [void]$failures.Add("templates/scripts *.sh count $shCount != bootstrap-manifest exact $expectedSh")
    }

    [void]$checks.Add([ordered]@{ name = 'script-manifest'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'tools/*.ps1 listed + shell count' })
    [void]$checks.Add([ordered]@{ name = 'safe-apply-contract'; status = 'ok'; detail = $(if ($Strict) { 'writes + writeRisk vs dry-run (strict)' } else { 'writes + writeRisk vs dry-run (warn)' }) })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-script-manifest' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-script-manifest: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
