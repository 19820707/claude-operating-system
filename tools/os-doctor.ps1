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
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/os-remediation-guidance.ps1')

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = '',
        [string]$Reason = '',
        [string]$Impact = '',
        [string]$Remediation = '',
        [string]$StrictImpact = '',
        [string]$DocsLink = ''
    )
    $f = New-OsDoctorCheckFinding -CheckName $Name -Status $Status -Detail $Detail
    if ($Reason) { $f.reason = $Reason }
    if ($Impact) { $f.impact = $Impact }
    if ($Remediation) { $f.remediation = $Remediation }
    if ($StrictImpact) { $f.strictImpact = $StrictImpact }
    if ($DocsLink) { $f.docsLink = $DocsLink }
    $script:Checks += [pscustomobject]@{
        name           = $Name
        status         = $Status
        detail         = $Detail
        reason         = [string]$f.reason
        impact         = [string]$f.impact
        remediation    = [string]$f.remediation
        strictImpact   = [string]$f.strictImpact
        docsLink       = [string]$f.docsLink
    }
}

function Get-CommandVersion {
    param(
        [string]$Command,
        [string[]]$CommandArguments = @('--version'),
        [int]$TimeoutMs = 12000
    )
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    $path = [string]$cmd.Source
    if ([string]::IsNullOrWhiteSpace($path)) { $path = $Command }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $path
        foreach ($a in $CommandArguments) {
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
    $version = Get-CommandVersion -Command $Command -CommandArguments $VersionArgs
    if ($version) {
        Add-Check -Name $Name -Status 'ok' -Detail "${Command}: $version"
    } else {
        Add-Check -Name $Name -Status $Severity -Detail "$Command not found" -Remediation "Install $Command for $RequiredFor."
    }
}

function Invoke-GitDoctorRead {
    param(
        [string[]]$Arguments,
        [int]$TimeoutMs = 8000
    )
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) { return $null }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = [string]$gitCmd.Source
    foreach ($a in $Arguments) { [void]$psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $RepoRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill($true) } catch { }
            return @{ timedOut = $true; text = '' }
        }
        $out = ($p.StandardOutput.ReadToEnd()).Trim()
        return @{ timedOut = $false; text = $out }
    } catch {
        return @{ timedOut = $false; text = '' }
    }
}

function Get-DoctorRepoState {
    $state = [ordered]@{
        root   = $RepoRoot
        branch = ''
        ahead  = 0
        behind = 0
        dirty  = $false
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        return [pscustomobject]$state
    }
    try {
        $brOut = Invoke-GitDoctorRead -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($brOut.timedOut) {
            Add-Check -Name 'git:rev-parse' -Status 'warn' -Detail 'git rev-parse timed out (doctor budget)' -Remediation 'Investigate hung git or repo locks.'
        } elseif ($brOut.text) { $state.branch = [string]$brOut.text.Trim() }

        $sbOut = Invoke-GitDoctorRead -Arguments @('status', '-sb')
        if ($sbOut.timedOut) {
            Add-Check -Name 'git:status-sb' -Status 'warn' -Detail 'git status -sb timed out (doctor budget)' -Remediation 'Investigate hung git or repo locks.'
        } else {
            $sb = @($sbOut.text -split "`r?`n") | Select-Object -First 1
            if ($sb -match 'ahead\s+(\d+)') { $state.ahead = [int]$Matches[1] }
            if ($sb -match 'behind\s+(\d+)') { $state.behind = [int]$Matches[1] }
        }

        $porOut = Invoke-GitDoctorRead -Arguments @('status', '--porcelain')
        if ($porOut.timedOut) {
            Add-Check -Name 'git:status-porcelain' -Status 'warn' -Detail 'git status --porcelain timed out (doctor budget)' -Remediation 'Investigate hung git or repo locks.'
        } else {
            $por = $porOut.text.Trim()
            $state.dirty = -not [string]::IsNullOrWhiteSpace($por)
        }
    } catch {
        # read-only; never fail doctor on git parse noise
    }
    return [pscustomobject]$state
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

$osDescription = try { [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim() } catch { 'unknown' }
$doctorEnv = [ordered]@{
    os              = $osDescription
    pwshVersion     = $PSVersionTable.PSVersion.ToString()
    gitVersion      = (Get-CommandVersion -Command 'git' -CommandArguments @('--version'))
    bashAvailable   = [bool](Get-Command bash -ErrorAction SilentlyContinue)
    nodeAvailable   = [bool](Get-Command node -ErrorAction SilentlyContinue)
    npmAvailable    = [bool](Get-Command npm -ErrorAction SilentlyContinue)
}
$doctorRepo = Get-DoctorRepoState

if ($Json) {
    $outChecks = foreach ($ch in $Checks) {
        $row = [ordered]@{
            name   = $ch.name
            status = $ch.status
            detail = (Redact-SensitiveText -Text ([string]$ch.detail) -MaxLength 280)
        }
        if ([string]$ch.status -ne 'ok') {
            $row.reason = (Redact-SensitiveText -Text ([string]$ch.reason) -MaxLength 400)
            $row.impact = (Redact-SensitiveText -Text ([string]$ch.impact) -MaxLength 400)
            $row.remediation = (Redact-SensitiveText -Text ([string]$ch.remediation) -MaxLength 400)
            $row.strictImpact = (Redact-SensitiveText -Text ([string]$ch.strictImpact) -MaxLength 400)
            $row.docsLink = (Redact-SensitiveText -Text ([string]$ch.docsLink) -MaxLength 200)
        }
        [pscustomobject]$row
    }
    [pscustomobject]@{
        status      = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
        failures    = $failures.Count
        warnings    = $warnings.Count
        environment = [pscustomobject]$doctorEnv
        repo          = $doctorRepo
        checks        = @($outChecks)
    } | ConvertTo-Json -Depth 10 -Compress | Write-Output
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
    if ([string]$check.status -ne 'ok') {
        if ($check.remediation) { Write-Host "       remediation: $($check.remediation)" }
        if ($check.docsLink) { Write-Host "       docs: $($check.docsLink)" }
    }
}
Write-Host ''
Write-Host "Doctor checks: $($Checks.Count), warnings: $($warnings.Count), failures: $($failures.Count)"
Write-Host ''
Write-Host 'Environment / repo (read-only):'
Write-Host ("  {0,-18} {1}" -f 'os', $doctorEnv.os)
Write-Host ("  {0,-18} {1}" -f 'pwshVersion', $doctorEnv.pwshVersion)
Write-Host ("  {0,-18} {1}" -f 'gitVersion', $doctorEnv.gitVersion)
Write-Host ("  {0,-18} {1}" -f 'bashAvailable', $doctorEnv.bashAvailable)
Write-Host ("  {0,-18} {1}" -f 'nodeAvailable', $doctorEnv.nodeAvailable)
Write-Host ("  {0,-18} {1}" -f 'npmAvailable', $doctorEnv.npmAvailable)
Write-Host ("  {0,-18} {1}" -f 'repo.root', $doctorRepo.root)
Write-Host ("  {0,-18} {1}" -f 'repo.branch', $doctorRepo.branch)
Write-Host ("  {0,-18} {1}" -f 'repo.ahead', $doctorRepo.ahead)
Write-Host ("  {0,-18} {1}" -f 'repo.behind', $doctorRepo.behind)
Write-Host ("  {0,-18} {1}" -f 'repo.dirty', $doctorRepo.dirty)

if ($failures.Count -gt 0) {
    throw 'Claude OS doctor found blocking environment issues.'
}
