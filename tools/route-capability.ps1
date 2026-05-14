# route-capability.ps1 — Intent routes (capability-manifest.json) + legacy registry (os-capabilities.json)
# Examples:
#   pwsh ./tools/route-capability.ps1 -Query "bootstrap a new project"
#   pwsh ./tools/route-capability.ps1 -RouteId route.release
#   pwsh ./tools/route-capability.ps1 -RouteId release
#   pwsh ./tools/route-capability.ps1 -Tag security
#   pwsh ./tools/route-capability.ps1 -Id os.health
#   pwsh ./tools/route-capability.ps1 -ListRoutes
#   pwsh ./tools/route-capability.ps1 -ListTags
#   pwsh ./tools/route-capability.ps1 -Query migration -Json

param(
    [string]$Query = '',
    [string]$Tag = '',
    [string]$Id = '',
    [string]$RouteId = '',
    [int]$Limit = 3,
    [switch]$ListTags,
    [switch]$ListRoutes,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$CapabilitiesPath = Join-Path $RepoRoot 'os-capabilities.json'
$ManifestPath = Join-Path $RepoRoot 'capability-manifest.json'

function Read-Capabilities {
    if (-not (Test-Path -LiteralPath $CapabilitiesPath)) {
        throw 'os-capabilities.json not found. Run from claude-operating-system or restore the registry.'
    }
    try { return Get-Content -LiteralPath $CapabilitiesPath -Raw | ConvertFrom-Json }
    catch { throw 'os-capabilities.json is invalid JSON.' }
}

function Read-IntentManifest {
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $null }
    try { return Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
    catch { throw 'capability-manifest.json is invalid JSON.' }
}

function Normalize-RouteId {
    param([string]$Raw)
    $t = $Raw.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    if ($t -match '^route\.') { return $t.ToLowerInvariant() }
    return ('route.' + $t.ToLowerInvariant())
}

function Get-RouteScore {
    param([object]$Route, [string[]]$Terms)
    $haystack = ((@(
        [string]$Route.id,
        [string]$Route.title,
        [string]$Route.summary,
        [string]$Route.operatingMode,
        [string]$Route.riskLevel,
        (@($Route.keywords) | ForEach-Object { [string]$_ }) -join ' ',
        (@($Route.tags) | ForEach-Object { [string]$_ }) -join ' ',
        (@($Route.relevantSkills) | ForEach-Object { [string]$_ }) -join ' '
    ) -join ' ').ToLowerInvariant())

    $score = 0
    foreach ($term in $Terms) {
        if (-not $term) { continue }
        if ($haystack.Contains($term)) { $score += 1 }
        if (([string]$Route.id).ToLowerInvariant().Contains($term)) { $score += 4 }
        if (([string]$Route.title).ToLowerInvariant().Contains($term)) { $score += 2 }
        if (@($Route.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $term) { $score += 4 }
        foreach ($kw in @($Route.keywords)) {
            if (([string]$kw).ToLowerInvariant() -eq $term) { $score += 3 }
        }
    }
    return $score
}

function Get-CapabilityScore {
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
        kind                  = 'registry-capability'
        id                    = [string]$Capability.id
        title                 = [string]$Capability.title
        intent                = [string]$Capability.intent
        skill                 = [string]$Capability.skill
        risk                  = [string]$Capability.risk
        cost                  = [string]$Capability.cost
        entrypoint            = [string]$Capability.entrypoint
        validations           = @($Capability.validations | ForEach-Object { [string]$_ })
        docs                  = @($Capability.docs | ForEach-Object { [string]$_ })
        tags                  = @($Capability.tags | ForEach-Object { [string]$_ })
        requiresHumanApproval = ($Capability.PSObject.Properties.Name -contains 'requiresHumanApproval') -and ([bool]$Capability.requiresHumanApproval)
    }
}

function Select-RouteFields {
    param([object]$Route)
    [pscustomobject]@{
        kind               = 'intent-route'
        id                 = [string]$Route.id
        title              = [string]$Route.title
        summary            = [string]$Route.summary
        keywords           = @($Route.keywords | ForEach-Object { [string]$_ })
        tags               = @($Route.tags | ForEach-Object { [string]$_ })
        operatingMode      = [string]$Route.operatingMode
        riskLevel          = [string]$Route.riskLevel
        requiredApproval   = [string]$Route.requiredApproval
        relevantSkills     = @($Route.relevantSkills | ForEach-Object { [string]$_ })
        relevantPlaybooks  = @($Route.relevantPlaybooks | ForEach-Object { [string]$_ })
        validators         = @($Route.validators | ForEach-Object { [string]$_ })
        expectedEvidence   = @($Route.expectedEvidence | ForEach-Object { [string]$_ })
        forbiddenShortcuts = @($Route.forbiddenShortcuts | ForEach-Object { [string]$_ })
        docs               = @($Route.docs | ForEach-Object { [string]$_ })
    }
}

if ($Limit -lt 1) { $Limit = 1 }
if ($Limit -gt 20) { $Limit = 20 }

$manifest = Read-IntentManifest
$routes = if ($manifest -and $manifest.routes) { @($manifest.routes) } else { @() }
$registry = Read-Capabilities
$capabilities = @($registry.capabilities)

if ($ListRoutes) {
    $list = @($routes | ForEach-Object { Select-RouteFields -Route $_ })
    if ($Json) {
        [pscustomobject]@{ kind = 'intent-routes'; count = $list.Count; results = $list } | ConvertTo-Json -Depth 10 -Compress | Write-Output
    }
    else {
        Write-Host "intent routes: $($list.Count)"
        foreach ($r in $list) {
            Write-Host "  $($r.id) — $($r.title) [$($r.operatingMode); $($r.riskLevel); approval=$($r.requiredApproval)]"
        }
    }
    exit 0
}

if ($ListTags) {
    $tagSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $capabilities) { foreach ($t in @($c.tags)) { [void]$tagSet.Add([string]$t) } }
    foreach ($r in $routes) { foreach ($t in @($r.tags)) { [void]$tagSet.Add([string]$t) } }
    $tags = @($tagSet | Sort-Object)
    if ($Json) {
        [pscustomobject]@{ tags = $tags; count = $tags.Count } | ConvertTo-Json -Depth 5 -Compress | Write-Output
    }
    else {
        Write-Host 'Capability and route tags:'
        foreach ($t in $tags) { Write-Host "  $t" }
    }
    exit 0
}

$results = @()
$kind = 'mixed'

if ($RouteId) {
    $rid = Normalize-RouteId -Raw $RouteId
    $results = @($routes | Where-Object { ([string]$_.id).ToLowerInvariant() -eq $rid } | ForEach-Object { Select-RouteFields -Route $_ })
    $kind = 'intent-routes'
}
elseif ($Id) {
    if ($Id -like 'route.*' -or ($Id -notlike 'os.*' -and ($routes | Where-Object { ([string]$_.id).ToLowerInvariant() -eq (Normalize-RouteId -Raw $Id) }).Count -gt 0)) {
        $rid = Normalize-RouteId -Raw $Id
        $results = @($routes | Where-Object { ([string]$_.id).ToLowerInvariant() -eq $rid } | ForEach-Object { Select-RouteFields -Route $_ })
        $kind = 'intent-routes'
    }
    if ($results.Count -eq 0 -and $Id -like 'os.*') {
        $results = @($capabilities | Where-Object { [string]$_.id -eq $Id } | ForEach-Object { Select-CapabilityFields -Capability $_ })
        $kind = 'registry-capabilities'
    }
    elseif ($results.Count -eq 0) {
        $results = @($capabilities | Where-Object { [string]$_.id -eq $Id } | ForEach-Object { Select-CapabilityFields -Capability $_ })
        $kind = 'registry-capabilities'
    }
}
elseif ($Tag) {
    $needle = $Tag.ToLowerInvariant()
    $fromRoutes = @($routes | Where-Object { @($_.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $needle } | ForEach-Object { Select-RouteFields -Route $_ })
    $fromCaps = @($capabilities | Where-Object { @($_.tags | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $needle } | ForEach-Object { Select-CapabilityFields -Capability $_ })
    $results = @($fromRoutes + $fromCaps) | Select-Object -First $Limit
    $kind = if ($fromRoutes.Count -gt 0 -and $fromCaps.Count -eq 0) { 'intent-routes' } elseif ($fromRoutes.Count -eq 0) { 'registry-capabilities' } else { 'mixed' }
}
elseif ($Query) {
    $terms = @($Query.ToLowerInvariant().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
    $scoredRoutes = @(
        $routes | ForEach-Object {
            $s = Get-RouteScore -Route $_ -Terms $terms
            if ($s -gt 0) { [pscustomobject]@{ item = $_; score = $s; tier = 0 } }
        } | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = { $_.item.id }; Ascending = $true }
    )
    $scoredCaps = @(
        $capabilities | ForEach-Object {
            $s = Get-CapabilityScore -Capability $_ -Terms $terms
            if ($s -gt 0) { [pscustomobject]@{ item = $_; score = $s; tier = 1 } }
        } | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = { $_.item.cost }; Ascending = $true }, @{ Expression = { $_.item.id }; Ascending = $true }
    )
    $picked = [System.Collections.Generic.List[object]]::new()
    foreach ($x in $scoredRoutes) {
        if ($picked.Count -ge $Limit) { break }
        [void]$picked.Add((Select-RouteFields -Route $x.item))
    }
    foreach ($x in $scoredCaps) {
        if ($picked.Count -ge $Limit) { break }
        [void]$picked.Add((Select-CapabilityFields -Capability $x.item))
    }
    $results = @($picked)
    if ($scoredRoutes.Count -gt 0 -and $scoredCaps.Count -eq 0) { $kind = 'intent-routes' }
    elseif ($scoredRoutes.Count -eq 0 -and $scoredCaps.Count -gt 0) { $kind = 'registry-capabilities' }
    elseif ($scoredRoutes.Count -gt 0) { $kind = 'mixed' }
    else { $kind = 'none' }
}
else {
    $results = @($routes | Select-Object -First $Limit | ForEach-Object { Select-RouteFields -Route $_ })
    if ($results.Count -eq 0) {
        $results = @($capabilities | Select-Object -First $Limit | ForEach-Object { Select-CapabilityFields -Capability $_ })
        $kind = 'registry-capabilities'
    }
    else { $kind = 'intent-routes' }
}

$results = @($results | Select-Object -First $Limit)

if ($Json) {
    [pscustomobject]@{ kind = $kind; count = $results.Count; results = $results } | ConvertTo-Json -Depth 12 -Compress | Write-Output
    exit 0
}

Write-Host "capability routes: $($results.Count)  ($kind)"
foreach ($r in $results) {
    Write-Host ''
    if ($r.kind -eq 'intent-route') {
        Write-Host "[$($r.id)] $($r.title)"
        Write-Host "  mode       : $($r.operatingMode)"
        Write-Host "  risk       : $($r.riskLevel)"
        Write-Host "  approval   : $($r.requiredApproval)"
        Write-Host "  summary    : $($r.summary)"
        Write-Host "  skills     : $(@($r.relevantSkills) -join ', ')"
        Write-Host "  playbooks  : $(@($r.relevantPlaybooks) -join ', ')"
        Write-Host "  validators : $(@($r.validators) -join ' ; ')"
        Write-Host "  evidence   : $(@($r.expectedEvidence) -join ' | ')"
        Write-Host "  avoid      : $(@($r.forbiddenShortcuts) -join ' | ')"
        Write-Host "  docs       : $(@($r.docs) -join ', ')"
    }
    else {
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
}

if ($results.Count -eq 0) {
    Write-Host ''
    Write-Host 'No matching route or capability. Try -ListRoutes, -ListTags, or a broader -Query.'
}
