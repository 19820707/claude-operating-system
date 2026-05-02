# os-doctor.ps1 — Claude OS runtime/environment diagnostics
# Run from repo root or any cwd:
#   pwsh ./tools/os-doctor.ps1
# Optional:
#   pwsh ./tools/os-doctor.ps1 -Json
#   pwsh ./tools/os-doctor.ps1 -Json -SkipBashSyntax

param(
    [switch]$Json,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Checks = @()

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = '',
        [string]$Remediation = ''
    )
    $script:Checks += [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        remediation = $Remediation
    }
}

function Get-CommandVersion {
    param(
        [string]$Command,
        [string[]]$Args = @('--version'),
        [int]$TimeoutMs = 12000
    )
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    $path = [string]$cmd.Source
    if ([string]::IsNullOrWhiteSpace($path)) { $path = $Command }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $path
        foreach ($a in $Args) {
            $psi.ArgumentList.Add($a)
        }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::new()
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill($true) } catch { }
            return 'installed'
        }
        $out = ($p.StandardOutput.ReadToEnd() -replace "`r`n|`n", ' ').Trim()
        if ($out) {
            return ($out -split '\s+')[0].Trim()
        }
    } catch {
        return 'installed'
    }
    return 'installed'
}

function Test-PathExists {
    param([string]$Name, [string]$RelativePath, [string]$Kind = 'path')
    $path = Join-Path $RepoRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Check -Name $Name -Status 'ok' -Detail "$Kind present: $RelativePath"
    } else {
        Add-Check -Name $Name -Status 'fail' -Detail "$Kind missing: $RelativePath" -Remediation 'Restore the file from the repository or rerun bootstrap validation.'
    }
}

function Test-CommandAvailable {
    param(
        [string]$Name,
        [string]$Command,
        [string]$RequiredFor,
        [string[]]$VersionArgs = @('--version'),
        [string]$Severity = 'fail'
    )
    $version = Get-CommandVersion -Command $Command -Args $VersionArgs
    if ($version) {
        Add-Check -Name $Name -Status 'ok' -Detail "${Command}: $version"
    } else {
        Add-Check -Name $Name -Status $Severity -Detail "$Command not found" -Remediation "Install $Command for $RequiredFor."
    }
}

function Test-ClaudeOsScaffoldSignals {
    $claudeDir = Join-Path $RepoRoot '.claude'
    if (-not (Test-Path -LiteralPath $claudeDir)) {
        Add-Check -Name 'project-scaffold' -Status 'warn' -Detail '.claude directory not present in this repo' -Remediation 'This is expected in the OS repo; project repos should run init-project.ps1.'
        return
    }
    foreach ($rel in @('.claude/docs-index.json', '.claude/os-capabilities.json', '.claude/scripts/route-capability.ps1')) {
        $p = Join-Path $RepoRoot $rel
        if (Test-Path -LiteralPath $p) {
            Add-Check -Name "scaffold:$rel" -Status 'ok' -Detail 'present'
        } else {
            Add-Check -Name "scaffold:$rel" -Status 'warn' -Detail 'missing' -Remediation 'Run init-project.ps1 from claude-operating-system to refresh project scaffold.'
        }
    }
}

# Invariant: doctor reports environment readiness only; it never mutates files.
Add-Check -Name 'repo-root' -Status 'ok' -Detail $RepoRoot
Test-PathExists -Name 'manifest' -RelativePath 'bootstrap-manifest.json' -Kind 'manifest'
Test-PathExists -Name 'docs-index' -RelativePath 'docs-index.json' -Kind 'index'
Test-PathExists -Name 'capabilities' -RelativePath 'os-capabilities.json' -Kind 'registry'
Test-PathExists -Name 'health-verifier' -RelativePath 'tools/verify-os-health.ps1' -Kind 'tool'

Test-CommandAvailable -Name 'powershell' -Command 'pwsh' -RequiredFor 'all validators and Windows bootstrap' -VersionArgs @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()')
if ($SkipBashSyntax -or -not $RequireBash) {
    Test-CommandAvailable -Name 'bash' -Command 'bash' -RequiredFor 'optional Bash hook syntax validation' -Severity 'warn'
} else {
    Test-CommandAvailable -Name 'bash' -Command 'bash' -RequiredFor 'template script syntax checks and project hooks'
}
Test-CommandAvailable -Name 'git' -Command 'git' -RequiredFor 'session drift, architecture graph, and bootstrap workflows'
Test-CommandAvailable -Name 'node' -Command 'node' -RequiredFor 'invariant-engine bundle development' -Severity 'warn'
Test-CommandAvailable -Name 'npm' -Command 'npm' -RequiredFor 'invariant-engine bundle rebuilds' -Severity 'warn'

$bundleDir = Join-Path $RepoRoot 'templates/invariant-engine/dist'
if (Test-Path -LiteralPath $bundleDir) {
    $bundles = @(Get-ChildItem -LiteralPath $bundleDir -Filter '*.cjs' -File)
    if ($bundles.Count -ge 3) {
        Add-Check -Name 'invariant-bundles' -Status 'ok' -Detail "$($bundles.Count) bundle(s) present"
    } else {
        Add-Check -Name 'invariant-bundles' -Status 'warn' -Detail "$($bundles.Count) bundle(s) present" -Remediation 'Run npm install && npm run build in templates/invariant-engine if bundle sources changed.'
    }
} else {
    Add-Check -Name 'invariant-bundles' -Status 'fail' -Detail 'templates/invariant-engine/dist missing' -Remediation 'Restore generated bundles or rebuild invariant engine.'
}

Test-ClaudeOsScaffoldSignals

$failures = @($Checks | Where-Object { $_.status -eq 'fail' })
$warnings = @($Checks | Where-Object { $_.status -eq 'warn' })

if ($Json) {
    [pscustomobject]@{
        status = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
        failures = $failures.Count
        warnings = $warnings.Count
        checks = $Checks
    } | ConvertTo-Json -Depth 6
    if ($failures.Count -gt 0) { exit 1 }
    exit 0
}

Write-Host 'claude-operating-system doctor'
Write-Host "Repo: $RepoRoot"
Write-Host ''
foreach ($check in $Checks) {
    $line = "  $($check.status.ToUpper().PadRight(4)) $($check.name)"
    if ($check.detail) { $line += " - $($check.detail)" }
    Write-Host $line
    if ($check.remediation -and $check.status -ne 'ok') {
        Write-Host "       fix: $($check.remediation)"
    }
}
Write-Host ''
Write-Host "Doctor checks: $($Checks.Count), warnings: $($warnings.Count), failures: $($failures.Count)"

if ($failures.Count -gt 0) {
    throw 'Claude OS doctor found blocking environment issues.'
}
