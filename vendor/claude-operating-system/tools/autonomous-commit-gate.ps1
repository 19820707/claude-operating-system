# autonomous-commit-gate.ps1 — Evidence gate for autonomous *local* commit (push never autonomous without human attestation)
#   pwsh ./tools/autonomous-commit-gate.ps1 -Json -ProposedCommitMessage "docs: clarify validation" `
#     -TypecheckNotApplicable -TestsNotApplicable [-MaxFiles 40] [-StewardApprovedPush]
#
# Requires explicit NA or commands for typecheck/tests when no default project commands exist.

[CmdletBinding()]
param(
    [string]$ProposedCommitMessage = '',
    [string]$ProposedCommitMessageFile,
    [int]$MaxFiles = 40,
    [string]$TypecheckCommand,
    [switch]$TypecheckNotApplicable,
    [string]$TestCommand,
    [switch]$TestsNotApplicable,
    [switch]$Json,
    [switch]$Strict,
    [switch]$StewardApprovedPush,
    [string]$StewardPushReason
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    [void]$checks.Add([ordered]@{ name = $Name; status = $Status; detail = (Redact-SensitiveText -Text $Detail -MaxLength 400) })
}

function Invoke-ExternalOk {
    param([string]$Label, [string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        Add-Check -Name $Label -Status 'fail' -Detail 'empty command'
        return $false
    }
    $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-WorkingDirectory', $RepoRoot, '-Command', $CommandLine) -PassThru -Wait -NoNewWindow
    if ($p.ExitCode -ne 0) {
        Add-Check -Name $Label -Status 'fail' -Detail "exit $($p.ExitCode)"
        return $false
    }
    Add-Check -Name $Label -Status 'ok' -Detail 'command succeeded'
    return $true
}

$msg = $ProposedCommitMessage
if ($ProposedCommitMessageFile) {
    $fp = if ([System.IO.Path]::IsPathRooted($ProposedCommitMessageFile)) { $ProposedCommitMessageFile } else { Join-Path $RepoRoot $ProposedCommitMessageFile }
    if (-not (Test-Path -LiteralPath $fp)) {
        Add-Check -Name 'commit_message' -Status 'fail' -Detail 'ProposedCommitMessageFile missing'
        $msg = ''
    }
    else {
        $msg = Get-Content -LiteralPath $fp -Raw -Encoding utf8
    }
}
$msg = ($msg -replace "`r`n", "`n").Trim()
if ([string]::IsNullOrWhiteSpace($msg)) {
    Add-Check -Name 'commit_message' -Status 'fail' -Detail 'Proposed commit message empty (must be supplied, not invented by tooling)'
}
elseif ($msg.Length -lt 12) {
    Add-Check -Name 'commit_message' -Status 'fail' -Detail 'Proposed commit message too short to be intentional'
}
elseif ($msg -match '^(wip|fixup!|squash!|asdf|test|todo)\s*$') {
    Add-Check -Name 'commit_message' -Status 'fail' -Detail 'Placeholder-style message rejected'
}
else {
    Add-Check -Name 'commit_message' -Status 'ok' -Detail 'proposed message present (human-supplied)'
}

# --- Git / diff scope ---
try {
    $null = & git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'not a git repository' }
    Add-Check -Name 'git_repo' -Status 'ok' -Detail 'inside git work tree'
}
catch {
    Add-Check -Name 'git_repo' -Status 'fail' -Detail $_.Exception.Message
}

$names = @()
try {
    $raw = & git -C $RepoRoot diff --name-only HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'git diff failed' }
    $names = @($raw | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
}
catch {
    Add-Check -Name 'git_diff' -Status 'fail' -Detail $_.Exception.Message
}

if ($names.Count -eq 0) {
    Add-Check -Name 'git_diff_scope' -Status 'fail' -Detail 'no diff against HEAD (nothing to commit)'
}
elseif ($names.Count -gt $MaxFiles) {
    Add-Check -Name 'git_diff_scope' -Status 'fail' -Detail "diff touches $($names.Count) files > MaxFiles=$MaxFiles"
}
else {
    Add-Check -Name 'git_diff_scope' -Status 'ok' -Detail "$($names.Count) file(s) in diff"
}

# Binary / risky diff filters
try {
    $num = @(& git -C $RepoRoot diff --numstat HEAD 2>$null)
    $bin = $false
    foreach ($line in $num) {
        if ($line -match '^\-\s+\-\s+') { $bin = $true }
    }
    $delFiles = @(& git -C $RepoRoot diff --diff-filter=D --name-only HEAD 2>$null)
    $del = $delFiles.Count -gt 0
    if ($bin) { Add-Check -Name 'rollback_trivial' -Status 'fail' -Detail 'binary diff detected (revert not text-trivial)' }
    elseif ($del) { Add-Check -Name 'rollback_trivial' -Status 'fail' -Detail 'deletes present; require human review' }
    else { Add-Check -Name 'rollback_trivial' -Status 'ok' -Detail 'text diff without deletes — revert via git revert expected trivial' }
}
catch {
    Add-Check -Name 'rollback_trivial' -Status 'fail' -Detail $_.Exception.Message
}

# Gated surfaces
$policyPath = Join-Path $RepoRoot 'policies/autonomous-commit-gated-paths.json'
$blocked = [System.Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $policyPath) {
    $pol = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
    $prefixes = @($pol.pathPrefixes | ForEach-Object { ([string]$_).Replace('\', '/').TrimEnd('/') })
    foreach ($n in $names) {
        $norm = ($n -replace '\\', '/')
        foreach ($pre in $prefixes) {
            $p = $pre.TrimEnd('/')
            if ($norm -eq $p -or $norm.StartsWith($p + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$blocked.Add($norm)
                break
            }
        }
    }
    if ($blocked.Count -gt 0) {
        Add-Check -Name 'gated_surface' -Status 'fail' -Detail ("touches gated path(s): " + (($blocked | Select-Object -Unique) -join ', '))
    }
    else {
        Add-Check -Name 'gated_surface' -Status 'ok' -Detail 'no autonomous-commit gated prefixes in diff'
    }
}
else {
    Add-Check -Name 'gated_surface' -Status 'fail' -Detail 'missing policies/autonomous-commit-gated-paths.json'
}

# no-secrets
$sec = Join-Path $RepoRoot 'tools/verify-no-secrets.ps1'
if (Test-Path -LiteralPath $sec) {
    $null = & pwsh -NoProfile -File $sec @('-Json')
    if ($LASTEXITCODE -ne 0) {
        Add-Check -Name 'no_secrets' -Status 'fail' -Detail 'verify-no-secrets exit non-zero'
    }
    else {
        Add-Check -Name 'no_secrets' -Status 'ok' -Detail 'verify-no-secrets passed'
    }
}
else {
    Add-Check -Name 'no_secrets' -Status 'fail' -Detail 'verify-no-secrets.ps1 missing'
}

# typecheck
if ($TypecheckNotApplicable) {
    Add-Check -Name 'typecheck' -Status 'ok' -Detail 'explicitly not_applicable (caller attestation)'
}
elseif ($TypecheckCommand) {
    $null = Invoke-ExternalOk -Label 'typecheck' -CommandLine $TypecheckCommand
}
else {
    Add-Check -Name 'typecheck' -Status 'fail' -Detail 'set -TypecheckCommand or -TypecheckNotApplicable'
}

# tests
if ($TestsNotApplicable) {
    Add-Check -Name 'tests' -Status 'ok' -Detail 'explicitly not_applicable (caller attestation)'
}
elseif ($TestCommand) {
    $null = Invoke-ExternalOk -Label 'tests' -CommandLine $TestCommand
}
else {
    Add-Check -Name 'tests' -Status 'fail' -Detail 'set -TestCommand or -TestsNotApplicable'
}

$anyFail = @($checks | Where-Object { $_.status -eq 'fail' }).Count -gt 0
$anyWarn = @($checks | Where-Object { $_.status -eq 'warn' }).Count -gt 0
$st = if ($anyFail) { 'fail' } elseif ($anyWarn) { 'warn' } else { 'ok' }

$commitAllowed = ($st -eq 'ok')
if ($Strict -and $st -eq 'warn') {
    $commitAllowed = $false
    $st = 'fail'
}

$pushAllowed = $false
if ($StewardApprovedPush) {
    if ([string]::IsNullOrWhiteSpace($StewardPushReason)) {
        [void]$checks.Add([ordered]@{ name = 'push_policy'; status = 'fail'; detail = 'StewardApprovedPush requires -StewardPushReason (human attestation)' })
        $st = 'fail'
        $commitAllowed = $false
    }
    else {
        $pushAllowed = $true
        [void]$checks.Add([ordered]@{ name = 'push_policy'; status = 'ok'; detail = "StewardApprovedPush attested: $(Redact-SensitiveText -Text $StewardPushReason -MaxLength 220)" })
    }
}
else {
    [void]$checks.Add([ordered]@{ name = 'push_policy'; status = 'ok'; detail = 'push not autonomous (pushAllowed=false unless -StewardApprovedPush + reason)' })
}

$out = [ordered]@{
    tool           = 'autonomous-commit-gate'
    status         = $st
    commitAllowed  = [bool]$commitAllowed
    pushAllowed    = [bool]$pushAllowed
    checks         = @($checks)
    durationMs     = 0
    warnings       = @()
    failures       = @()
    findings       = @(@{ maxFiles = $MaxFiles })
    actions        = @()
}

if ($Json) {
    $out | ConvertTo-Json -Depth 10 -Compress | Write-Output
}
else {
    Write-Host "autonomous-commit-gate: $($out.status) commitAllowed=$($out.commitAllowed) pushAllowed=$($out.pushAllowed)"
}

if (-not $commitAllowed) { exit 1 }
exit 0
