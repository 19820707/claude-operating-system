# build-distribution.ps1 — Stage files per distribution-manifest.json and produce a zip
#   pwsh ./tools/build-distribution.ps1 [-WhatIf] [-Json]
#   pwsh ./tools/build-distribution.ps1 -Confirm:$false   # non-interactive dry preview

[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')
. (Join-Path $RepoRoot 'tools/lib/distribution-resolve.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()
$actions = [System.Collections.Generic.List[string]]::new()

try {
    $mf = Import-DistributionManifest -Root $RepoRoot
    foreach ($rf in @($mf.rootFiles | ForEach-Object { [string]$_ })) {
        $p = Join-Path $RepoRoot ($rf -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $p)) {
            [void]$failures.Add("missing rootFile: $rf")
        }
    }
    foreach ($mp in @($mf.mandatoryPackagedPaths | ForEach-Object { [string]$_ })) {
        $p = Join-Path $RepoRoot ($mp -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $p)) {
            [void]$failures.Add("missing mandatoryPackagedPaths source: $mp")
        }
    }

    if ($failures.Count -gt 0) {
        throw 'prerequisite paths missing'
    }

    $files = Get-DistributionPackagedRelativePaths -RepoRoot $RepoRoot -Manifest $mf
    [void]$findings.Add([ordered]@{ packagedFileCount = $files.Count })

    $stagingRel = [string]$mf.stagingDirectoryRelative
    $staging = Join-Path $RepoRoot ($stagingRel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
    $zipRel = [string]$mf.outputZipRelative
    $zipOut = Join-Path $RepoRoot ($zipRel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)

    if (-not $PSCmdlet.ShouldProcess($zipOut, "package $($files.Count) files into distribution zip")) {
        [void]$warnings.Add('WhatIf: no zip written; file list resolved successfully')
        [void]$actions.Add("would write $zipOut ($($files.Count) files)")
    }
    else {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop
        }
        $null = New-Item -ItemType Directory -Path $staging -Force

        foreach ($rel in $files) {
            $src = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            $dest = Join-Path $staging ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destDir)) {
                $null = New-Item -ItemType Directory -Path $destDir -Force
            }
            Copy-Item -LiteralPath $src -Destination $dest -Force
        }

        $zipParent = Split-Path -Parent $zipOut
        if (-not (Test-Path -LiteralPath $zipParent)) {
            $null = New-Item -ItemType Directory -Path $zipParent -Force
        }
        if (Test-Path -LiteralPath $zipOut) {
            Remove-Item -LiteralPath $zipOut -Force
        }
        if (-not (Get-Command Compress-Archive -ErrorAction SilentlyContinue)) {
            throw 'Compress-Archive not available in this host'
        }
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipOut -CompressionLevel Optimal -Force
        [void]$actions.Add("wrote $zipOut")
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop
    }

    [void]$checks.Add([ordered]@{
            name   = 'distribution-pack'
            status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
            detail = "resolved $($files.Count) paths"
        })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'build-distribution' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings) -Actions @($actions)

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "build-distribution: $($env.status)"
    foreach ($a in @($env.actions)) { Write-Host "  $a" }
    foreach ($w in @($env.warnings)) { Write-Host "WARN: $w" }
    foreach ($f in @($env.failures)) { Write-Host "FAIL: $f" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
