# verify-git-hygiene.ps1 — Read-only Git workspace hygiene (no reset, no stash, no mutations)
#   pwsh ./tools/verify-git-hygiene.ps1
#   pwsh ./tools/verify-git-hygiene.ps1 -Json
#   pwsh ./tools/verify-git-hygiene.ps1 -Strict   # nested clone + nested .git become blocking failures (release / os-validate-all -Strict)

param(
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

$script:HygieneFails = [System.Collections.Generic.List[string]]::new()
$script:HygieneWarns = [System.Collections.Generic.List[string]]::new()

function Add-Fail {
    param([string]$Msg)
    [void]$script:HygieneFails.Add((Redact-SensitiveText -Text $Msg -MaxLength 400))
}

function Add-Warn {
    param([string]$Msg)
    [void]$script:HygieneWarns.Add((Redact-SensitiveText -Text $Msg -MaxLength 400))
}

function Invoke-GitOut {
    param([string[]]$GitArguments)
    Push-Location $RepoRoot
    try {
        return (& git @GitArguments 2>$null | Out-String).Trim()
    } finally {
        Pop-Location
    }
}

function Invoke-GitOk {
    param([string[]]$GitArguments)
    Push-Location $RepoRoot
    try {
        & git @GitArguments 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

$rootGit = Join-Path $RepoRoot '.git'
if (-not (Test-Path -LiteralPath $rootGit)) {
    Add-Fail 'No .git at repository root (not a Git checkout).'
}

# Known Windows/Cursor footgun: nested clone at ./claude-operating-system (also listed in .gitignore).
# Never delete automatically — human review first. Suggested remediation after review:
#   Remove-Item -Recurse -Force .\claude-operating-system
$nestedCloneDir = Join-Path $RepoRoot 'claude-operating-system'
$nestedCloneFull = $null
if (Test-Path -LiteralPath $nestedCloneDir) {
    $nestedCloneFull = [System.IO.Path]::GetFullPath($nestedCloneDir).TrimEnd('\', '/')
    $isCi = ($env:CI -eq 'true') -or ($env:GITHUB_ACTIONS -eq 'true')
    $msg = 'Nested folder claude-operating-system/ at repo root — accidental nested clone. Do not use git add . Review contents, then after human approval only: Remove-Item -Recurse -Force .\claude-operating-system (or move outside repo).'
    if ($Strict -or $isCi) {
        Add-Fail $msg
    } else {
        Add-Warn $msg
    }
}

# Nested .git directories (exclude root). Bounded depth; skip node_modules; skip scanning *inside* known nested clone tree (folder rule covers it).
$expectedRootGitFull = [System.IO.Path]::GetFullPath($rootGit).TrimEnd('\', '/')
$rawNested = @(
    try {
        Get-ChildItem -LiteralPath $RepoRoot -Force -Depth 14 -Recurse -Directory -Filter '.git' -ErrorAction SilentlyContinue
    } catch {
        @()
    }
)
$nestedGits = @(
    foreach ($item in $rawNested) {
        $p = $item.FullName.TrimEnd('\', '/')
        if ($p.Equals($expectedRootGitFull, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($item.FullName -match '[\\/]node_modules[\\/]') { continue }
        if ($null -ne $nestedCloneFull) {
            $prefA = $nestedCloneFull + '\'
            $prefB = $nestedCloneFull + '/'
            if ($p.StartsWith($prefA, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($prefB, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }
        $item
    }
)
foreach ($g in $nestedGits) {
    $rel = try {
        $full = $g.FullName
        $rr = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
        if ($full.StartsWith($rr, [StringComparison]::OrdinalIgnoreCase)) {
            '.' + $full.Substring($rr.Length)
        } else {
            (Split-Path -Path $full -Parent | Split-Path -Leaf) + '/.git'
        }
    } catch {
        'nested/.git'
    }
    Add-Fail "Nested .git directory under repo (not root): $(Redact-SensitiveText -Text $rel -MaxLength 200). Remove nested clone or submodule after human review; never delete automatically."
}

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git/rebase-merge')) { Add-Fail 'Rebase in progress (.git/rebase-merge). Resolve or continue rebase before shipping.' }
if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git/rebase-apply')) { Add-Fail 'Rebase in progress (.git/rebase-apply). Resolve or continue rebase before shipping.' }
if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git/MERGE_HEAD')) { Add-Fail 'Merge in progress (.git/MERGE_HEAD). Complete or abort merge after review.' }
if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git/CHERRY_PICK_HEAD')) { Add-Fail 'Cherry-pick in progress (.git/CHERRY_PICK_HEAD). Complete or abort after review.' }

# Unmerged paths (stderr must not pollute file list — e.g. CRLF warnings)
$unmerged = @(
    (Invoke-GitOut @('diff', '--name-only', '--diff-filter=U')) -split "`r?`n" |
        Where-Object { $_ -and ($_ -notmatch '^(warning|error):') }
)
foreach ($u in $unmerged) {
    if ([string]::IsNullOrWhiteSpace($u)) { continue }
    Add-Fail "Unmerged (conflict) path: $u"
}

# Conflict markers in tracked content (git grep is authoritative when available)
foreach ($pat in @('^<<<<<<< ', '^=======$', '^>>>>>>> ')) {
    if (Invoke-GitOk @('grep', '-q', '-I', '--no-color', $pat, '--')) {
        Add-Fail "Conflict markers ($pat) found in tracked repository content. Fix before commit."
        break
    }
}

# Critical paths must not be conflicted / missing merge — already unmerged; optional explicit list
$critical = @(
    'tools/os-runtime.ps1',
    'tools/os-validate-all.ps1',
    'tools/verify-os-health.ps1',
    'tools/os-doctor.ps1'
)
foreach ($rel in $critical) {
    if ($unmerged -contains $rel) {
        Add-Fail "Critical path in merge conflict: $rel"
    }
}

# Branch + ahead/behind + dirty
$branch = ''
try {
    $branch = (Invoke-GitOut @('rev-parse', '--abbrev-ref', 'HEAD')).Trim()
} catch {
    $branch = '(unknown)'
}

$porcelain = Invoke-GitOut @('status', '--porcelain')
$dirty = -not [string]::IsNullOrWhiteSpace($porcelain)
if ($dirty) {
    $isCi = ($env:CI -eq 'true') -or ($env:GITHUB_ACTIONS -eq 'true')
    if ($isCi) {
        Add-Fail 'Working tree not clean (CI requires clean checkout).'
    } else {
        Add-Warn 'Working tree has local changes or untracked files. Commit or stash before push when appropriate.'
    }
}

$ahead = 0
$behind = 0
$sb = Invoke-GitOut @('status', '-sb')
if ($sb -match 'ahead\s+(\d+)') { $ahead = [int]$Matches[1] }
if ($sb -match 'behind\s+(\d+)') { $behind = [int]$Matches[1] }
if ($ahead -gt 0 -or $behind -gt 0) {
    Add-Warn "Branch sync: ahead=$ahead behind=$behind (push or pull as appropriate)."
}

# Dangerous untracked directories (names only)
$lines = @($porcelain -split "`r?`n" | Where-Object { $_ -match '^\?\?' })
foreach ($line in $lines) {
    $path = ($line -replace '^\?\?\s+', '').Trim()
    if ($path -match '(?i)claude-operating-system') {
        Add-Fail "Untracked nested repo path detected: $path — treat as FAIL; do not git add ."
    }
}

$result = [ordered]@{
    repoRoot     = $RepoRoot
    branch       = $branch
    ahead        = $ahead
    behind       = $behind
    dirty        = [bool]$dirty
    strict       = [bool]$Strict
    failures     = @($script:HygieneFails)
    warnings     = @($script:HygieneWarns)
    status       = if ($script:HygieneFails.Count -gt 0) { 'fail' } elseif ($script:HygieneWarns.Count -gt 0) { 'warn' } else { 'ok' }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
} else {
    Write-Host 'verify-git-hygiene'
    $sum = if ($result.status -eq 'ok') { 'ok' } elseif ($result.status -eq 'warn') { 'warn' } else { 'fail' }
    Write-StatusLine -Status $sum -Name 'git-hygiene' -Detail "branch=$branch dirty=$dirty ahead=$ahead behind=$behind"
    foreach ($f in $script:HygieneFails) { Write-StatusLine -Status 'fail' -Name 'rule' -Detail $f }
    foreach ($w in $script:HygieneWarns) { Write-StatusLine -Status 'warn' -Name 'rule' -Detail $w }
}

if ($script:HygieneFails.Count -gt 0) {
    throw "Git hygiene failed: $($script:HygieneFails.Count) issue(s)."
}
