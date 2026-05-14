# query-docs-index.ps1 — Cheap section-first retrieval over docs-index.json
# Examples:
#   pwsh ./tools/query-docs-index.ps1 -Query bootstrap
#   pwsh ./tools/query-docs-index.ps1 -Tag validation
#   pwsh ./tools/query-docs-index.ps1 -Id root/health
#   pwsh ./tools/query-docs-index.ps1 -ListTags

param(
    [string]$Query = '',
    [string]$Tag = '',
    [string]$Id = '',
    [int]$Limit = 8,
    [switch]$ListTags,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$IndexPath = Join-Path $RepoRoot 'docs-index.json'

function Fail-Safe {
    param([string]$Message)
    throw $Message
}

function Get-DocsIndex {
    if (-not (Test-Path -LiteralPath $IndexPath)) {
        Fail-Safe "docs-index.json not found. Run from claude-operating-system or restore the index."
    }
    try {
        return Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
    } catch {
        Fail-Safe 'docs-index.json is invalid JSON.'
    }
}

function Get-Score {
    param([object]$Section, [string[]]$Terms)
    $haystack = ((@(
        [string]$Section.id,
        [string]$Section.path,
        [string]$Section.title,
        [string]$Section.purpose,
        (@($Section.tags) -join ' ')
    ) -join ' ').ToLowerInvariant())

    $score = 0
    foreach ($term in $Terms) {
        if (-not $term) { continue }
        if ($haystack.Contains($term)) { $score += 1 }
        if (([string]$Section.id).ToLowerInvariant().Contains($term)) { $score += 2 }
        if (([string]$Section.title).ToLowerInvariant().Contains($term)) { $score += 2 }
        if (@($Section.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $term) { $score += 3 }
    }
    return $score
}

function Select-SectionFields {
    param([object]$Section)
    [pscustomobject]@{
        id = [string]$Section.id
        path = [string]$Section.path
        title = [string]$Section.title
        purpose = [string]$Section.purpose
        tags = @($Section.tags | ForEach-Object { [string]$_ })
        command = if ($Section.PSObject.Properties.Name -contains 'command') { [string]$Section.command } else { '' }
    }
}

if ($Limit -lt 1) { $Limit = 1 }
if ($Limit -gt 50) { $Limit = 50 }

$index = Get-DocsIndex
$sections = @($index.sections)

if ($ListTags) {
    $tags = $sections | ForEach-Object { $_.tags } | ForEach-Object { [string]$_ } | Sort-Object -Unique
    if ($Json) {
        [pscustomobject]@{ tags = @($tags); count = @($tags).Count } | ConvertTo-Json -Depth 4 -Compress | Write-Output
    } else {
        Write-Host 'Tags:'
        foreach ($t in $tags) { Write-Host "  $t" }
    }
    exit 0
}

$matches = @()
if ($Id) {
    $matches = @($sections | Where-Object { [string]$_.id -eq $Id })
} elseif ($Tag) {
    $needle = $Tag.ToLowerInvariant()
    $matches = @($sections | Where-Object { @($_.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $needle })
} elseif ($Query) {
    $terms = @($Query.ToLowerInvariant().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
    $matches = @(
        $sections |
            ForEach-Object {
                $score = Get-Score -Section $_ -Terms $terms
                if ($score -gt 0) {
                    [pscustomobject]@{ section = $_; score = $score }
                }
            } |
            Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = { $_.section.id }; Ascending = $true } |
            Select-Object -First $Limit |
            ForEach-Object { $_.section }
    )
} else {
    $matches = @($sections | Select-Object -First $Limit)
}

$result = @($matches | Select-Object -First $Limit | ForEach-Object { Select-SectionFields -Section $_ })

if ($Json) {
    [pscustomobject]@{
        count = $result.Count
        results = $result
    } | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}

Write-Host "docs-index results: $($result.Count)"
foreach ($r in $result) {
    Write-Host ""
    Write-Host "[$($r.id)] $($r.title)"
    Write-Host "  path   : $($r.path)"
    Write-Host "  purpose: $($r.purpose)"
    Write-Host "  tags   : $(@($r.tags) -join ', ')"
    if ($r.command) { Write-Host "  command: $($r.command)" }
}

if ($result.Count -eq 0) {
    Write-Host ''
    Write-Host 'No matching sections. Try -ListTags or a broader -Query.'
}
