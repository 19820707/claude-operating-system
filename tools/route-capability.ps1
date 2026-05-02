# route-capability.ps1 — Cheap intent router over os-capabilities.json
# Examples:
#   pwsh ./tools/route-capability.ps1 -Query "bootstrap a new project"
#   pwsh ./tools/route-capability.ps1 -Tag security
#   pwsh ./tools/route-capability.ps1 -Id os.health
#   pwsh ./tools/route-capability.ps1 -ListTags

param(
    [string]$Query = '',
    [string]$Tag = '',
    [string]$Id = '',
    [int]$Limit = 3,
    [switch]$ListTags,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$CapabilitiesPath = Join-Path $RepoRoot 'os-capabilities.json'

function Read-Capabilities {
    if (-not (Test-Path -LiteralPath $CapabilitiesPath)) {
        throw 'os-capabilities.json not found. Run from claude-operating-system or restore the registry.'
    }
    try { return Get-Content -LiteralPath $CapabilitiesPath -Raw | ConvertFrom-Json }
    catch { throw 'os-capabilities.json is invalid JSON.' }
}

function Get-Score {
    param([object]$Capability, [string[]]$Terms)
    $haystack = ((@(
        [string]$Capability.id,
        [string]$Capability.title,
        [string]$Capability.intent,
        [string]$Capability.skill,
        [string]$Capability.risk,
        [string]$Capability.cost,
        (@($Capability.tags) -join ' '),
        (@($Capability.docs) -join ' ')
    ) -join ' ').ToLowerInvariant())

    $score = 0
    foreach ($term in $Terms) {
        if (-not $term) { continue }
        if ($haystack.Contains($term)) { $score += 1 }
        if (([string]$Capability.id).ToLowerInvariant().Contains($term)) { $score += 3 }
        if (([string]$Capability.title).ToLowerInvariant().Contains($term)) { $score += 2 }
        if (@($Capability.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $term) { $score += 4 }
        if (([string]$Capability.skill).ToLowerInvariant().Contains($term)) { $score += 2 }
    }
    return $score
}

function Select-CapabilityFields {
    param([object]$Capability)
    [pscustomobject]@{
        id = [string]$Capability.id
        title = [string]$Capability.title
        intent = [string]$Capability.intent
        skill = [string]$Capability.skill
        risk = [string]$Capability.risk
        cost = [string]$Capability.cost
        entrypoint = [string]$Capability.entrypoint
        validations = @($Capability.validations | ForEach-Object { [string]$_ })
        docs = @($Capability.docs | ForEach-Object { [string]$_ })
        tags = @($Capability.tags | ForEach-Object { [string]$_ })
        requiresHumanApproval = ($Capability.PSObject.Properties.Name -contains 'requiresHumanApproval') -and ([bool]$Capability.requiresHumanApproval)
    }
}

if ($Limit -lt 1) { $Limit = 1 }
if ($Limit -gt 20) { $Limit = 20 }

$registry = Read-Capabilities
$capabilities = @($registry.capabilities)

if ($ListTags) {
    $tags = $capabilities | ForEach-Object { $_.tags } | ForEach-Object { [string]$_ } | Sort-Object -Unique
    if ($Json) {
        [pscustomobject]@{ tags = @($tags); count = @($tags).Count } | ConvertTo-Json -Depth 5 -Compress | Write-Output
    } else {
        Write-Host 'Capability tags:'
        foreach ($t in $tags) { Write-Host "  $t" }
    }
    exit 0
}

$capabilityMatches = @()
if ($Id) {
    $capabilityMatches = @($capabilities | Where-Object { [string]$_.id -eq $Id })
} elseif ($Tag) {
    $needle = $Tag.ToLowerInvariant()
    $capabilityMatches = @($capabilities | Where-Object { @($_.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $needle })
} elseif ($Query) {
    $terms = @($Query.ToLowerInvariant().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
    $capabilityMatches = @(
        $capabilities |
            ForEach-Object {
                $score = Get-Score -Capability $_ -Terms $terms
                if ($score -gt 0) { [pscustomobject]@{ capability = $_; score = $score } }
            } |
            Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = { $_.capability.cost }; Ascending = $true }, @{ Expression = { $_.capability.id }; Ascending = $true } |
            Select-Object -First $Limit |
            ForEach-Object { $_.capability }
    )
} else {
    $capabilityMatches = @($capabilities | Select-Object -First $Limit)
}

$result = @($capabilityMatches | Select-Object -First $Limit | ForEach-Object { Select-CapabilityFields -Capability $_ })

if ($Json) {
    [pscustomobject]@{ count = $result.Count; results = $result } | ConvertTo-Json -Depth 8 -Compress | Write-Output
    exit 0
}

Write-Host "capability routes: $($result.Count)"
foreach ($r in $result) {
    Write-Host ''
    Write-Host "[$($r.id)] $($r.title)"
    Write-Host "  intent : $($r.intent)"
    Write-Host "  skill  : $($r.skill)"
    Write-Host "  risk   : $($r.risk)"
    Write-Host "  cost   : $($r.cost)"
    Write-Host "  run    : $($r.entrypoint)"
    Write-Host "  docs   : $(@($r.docs) -join ', ')"
    Write-Host "  checks : $(@($r.validations) -join ' ; ')"
    if ($r.requiresHumanApproval) { Write-Host '  gate   : human approval required' }
}

if ($result.Count -eq 0) {
    Write-Host ''
    Write-Host 'No matching capability. Try -ListTags or a broader -Query.'
}
