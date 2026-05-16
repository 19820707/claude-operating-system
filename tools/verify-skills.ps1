# verify-skills.ps1 — Validate Claude OS source/skills definitions
# Run from repo root or any cwd (uses script location):
#   pwsh ./tools/verify-skills.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $RepoRoot "bootstrap-manifest.json"
$skillsRoot = Join-Path $RepoRoot "source/skills"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "bootstrap-manifest.json not found at $manifestPath"
}
if (-not (Test-Path -LiteralPath $skillsRoot)) {
    throw "source/skills not found at $skillsRoot"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.skills) {
    throw "bootstrap-manifest.json missing skills section"
}

$expectedCount = [int]$manifest.skills.exact
$allowedCategories = @($manifest.skills.categories | ForEach-Object { [string]$_ })
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Key
    )
    $pattern = "(?m)^" + [regex]::Escape($Key) + "\s*:\s*(.+?)\s*$"
    $m = [regex]::Match($Frontmatter, $pattern)
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value.Trim().Trim('"').Trim("'")
}

Write-Host "verify-skills"
Write-Host "Repo   : $RepoRoot"
Write-Host "Skills : $skillsRoot"
Write-Host ""

$skillDirs = @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)
if ($skillDirs.Count -ne $expectedCount) {
    Fail "expected exactly $expectedCount skills, found $($skillDirs.Count)"
}

$names = @{}
foreach ($dir in $skillDirs) {
    $skillFile = Join-Path $dir.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile)) {
        Fail "$($dir.Name): missing SKILL.md"
        continue
    }

    $content = Get-Content -LiteralPath $skillFile -Raw
    if (-not $content.StartsWith("---`n") -and -not $content.StartsWith("---`r`n")) {
        Fail "$($dir.Name): missing YAML frontmatter start"
        continue
    }

    $frontmatterMatch = [regex]::Match($content, "(?s)^---\r?\n(.+?)\r?\n---\r?\n")
    if (-not $frontmatterMatch.Success) {
        Fail "$($dir.Name): malformed YAML frontmatter"
        continue
    }

    $frontmatter = $frontmatterMatch.Groups[1].Value
    $name = Get-FrontmatterValue -Frontmatter $frontmatter -Key "name"
    $description = Get-FrontmatterValue -Frontmatter $frontmatter -Key "description"
    $category = Get-FrontmatterValue -Frontmatter $frontmatter -Key "category"
    $version = Get-FrontmatterValue -Frontmatter $frontmatter -Key "version"
    $userInvocable = Get-FrontmatterValue -Frontmatter $frontmatter -Key "user-invocable"

    if (-not $name) { Fail "$($dir.Name): missing name"; continue }
    if ($name -ne $dir.Name) { Fail "$($dir.Name): name '$name' must match directory name" }
    if ($name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { Fail "$($dir.Name): invalid skill name '$name'" }
    if ($names.ContainsKey($name)) { Fail "$($dir.Name): duplicate skill name '$name'" }
    $names[$name] = $true

    if (-not $description) {
        Fail "$($dir.Name): missing description"
    } elseif (-not $description.StartsWith("Use when ")) {
        Fail "$($dir.Name): description must start with 'Use when '"
    }

    if (-not $category) {
        Fail "$($dir.Name): missing category"
    } elseif ($allowedCategories -notcontains $category) {
        Fail "$($dir.Name): category '$category' is not declared in bootstrap-manifest.json"
    }

    if (-not $version) { Fail "$($dir.Name): missing version" }
    if ($userInvocable -notin @("true", "false")) { Fail "$($dir.Name): user-invocable must be true or false" }

    $links = [regex]::Matches($content, "\]\(([^)]+)\)")
    foreach ($link in $links) {
        $target = $link.Groups[1].Value
        if ($target -match '^[a-z]+:' -or $target.StartsWith('#')) { continue }
        if ([System.IO.Path]::IsPathRooted($target) -or $target -match '(^|[\\/])\.\.([\\/]|$)') {
            Fail "$($dir.Name): unsafe relative link '$target'"
            continue
        }
        $targetPath = Join-Path $dir.FullName ($target -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $targetPath)) {
            Fail "$($dir.Name): broken relative link '$target'"
        }
    }

    Write-Host "OK:  $name ($category)"
}

if ($failed) {
    throw "Skill verification failed. Update source/skills or bootstrap-manifest.json."
}

Write-Host ""
Write-Host "All skill checks passed."
exit 0
