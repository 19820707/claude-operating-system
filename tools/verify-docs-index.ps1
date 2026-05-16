# verify-docs-index.ps1 — Validate docs-index.json section navigation contract
# Run from repo root or any cwd (uses script location):
#   pwsh ./tools/verify-docs-index.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$indexPath = Join-Path $RepoRoot 'docs-index.json'
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Test-SafeRelativePath {
    param([string]$Path, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail "empty path in $Field"
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        Fail "unsafe relative path '$Path' in $Field"
        return $null
    }
    return ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "docs-index.json not found at $indexPath"
}

try {
    $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
} catch {
    throw 'docs-index.json is not valid JSON'
}

if (-not $index.sections) {
    throw 'docs-index.json missing sections array'
}

Write-Host 'verify-docs-index'
Write-Host "Repo : $RepoRoot"
Write-Host "Index: $indexPath"
Write-Host ''

$seen = @{}
$sectionCount = 0
foreach ($section in @($index.sections)) {
    $sectionCount++
    $id = [string]$section.id
    $path = [string]$section.path
    $title = [string]$section.title
    $purpose = [string]$section.purpose
    $tags = @($section.tags | ForEach-Object { [string]$_ })

    if ([string]::IsNullOrWhiteSpace($id)) {
        Fail "section #$sectionCount has empty id"
        continue
    }
    if ($id -notmatch '^[a-z0-9][a-z0-9/_-]*$') {
        Fail "section '$id' has invalid id format"
    }
    if ($seen.ContainsKey($id)) {
        Fail "duplicate section id '$id'"
    }
    $seen[$id] = $true

    $safePath = Test-SafeRelativePath -Path $path -Field "section '$id'.path"
    if ($safePath) {
        $full = Join-Path $RepoRoot $safePath
        if (-not (Test-Path -LiteralPath $full)) {
            Fail "section '$id' points to missing path: $path"
        }
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        Fail "section '$id' has empty title"
    }
    if ([string]::IsNullOrWhiteSpace($purpose)) {
        Fail "section '$id' has empty purpose"
    }
    if ($tags.Count -eq 0) {
        Fail "section '$id' has no tags"
    }
    foreach ($tag in $tags) {
        if ($tag -notmatch '^[a-z0-9][a-z0-9-]*$') {
            Fail "section '$id' has invalid tag '$tag'"
        }
    }

    if ($section.PSObject.Properties.Name -contains 'command') {
        $command = [string]$section.command
        if ($command -match '[`;&|]') {
            Fail "section '$id' has unsafe command metacharacter"
        }
        if ($command -notmatch '^pwsh \./tools/[a-z0-9-]+\.ps1( .*)?$') {
            Fail "section '$id' command must be a repo-local pwsh tools invocation"
        }
    }

    Write-Host "OK:  $id -> $path"
}

if ($sectionCount -lt 12) {
    Fail "docs-index.json expected at least 12 sections, found $sectionCount"
}

if ($failed) {
    throw 'Docs index verification failed.'
}

Write-Host ''
Write-Host "Docs index checks passed ($sectionCount sections)."
exit 0
