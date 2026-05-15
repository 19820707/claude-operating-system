# verify-capabilities.ps1 — Validate os-capabilities.json + capability-manifest.json routing contracts
# Run from repo root or any cwd:
#   pwsh ./tools/verify-capabilities.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$capPath = Join-Path $RepoRoot 'os-capabilities.json'
$routePath = Join-Path $RepoRoot 'capability-manifest.json'
$playPath = Join-Path $RepoRoot 'playbook-manifest.json'
$docsPath = Join-Path $RepoRoot 'docs-index.json'
$skillsRoot = Join-Path $RepoRoot 'source/skills'
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Read-JsonFile {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Name not found at $Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "$Name is invalid JSON" }
}

function Test-SafeCommand {
    param([string]$Command, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Command)) {
        Fail "$Field is empty"
        return
    }
    if ($Command -match '[`;&|]') {
        Fail "$Field contains unsafe shell metacharacter"
    }
    if ($Command -match '\.\.') {
        Fail "$Field contains path traversal marker"
    }
}

Write-Host 'verify-capabilities'
Write-Host "Repo: $RepoRoot"
Write-Host ''

$cap = Read-JsonFile -Path $capPath -Name 'os-capabilities.json'
$docs = Read-JsonFile -Path $docsPath -Name 'docs-index.json'
$routesDoc = Read-JsonFile -Path $routePath -Name 'capability-manifest.json'
$play = Read-JsonFile -Path $playPath -Name 'playbook-manifest.json'

if (-not $cap.capabilities) { throw 'os-capabilities.json missing capabilities array' }
if (-not $routesDoc.routes) { throw 'capability-manifest.json missing routes array' }

$docIds = @{}
foreach ($section in @($docs.sections)) { $docIds[[string]$section.id] = $true }

$skillNames = @{}
Get-ChildItem -LiteralPath $skillsRoot -Directory | ForEach-Object { $skillNames[$_.Name] = $true }

$playbookIds = @{}
foreach ($pb in @($play.playbooks)) { $playbookIds[[string]$pb.id] = $true }

$allowedRisk = @('low', 'medium', 'high', 'critical')
$allowedCost = @('low', 'medium', 'high')
$criticalTags = @('security', 'production', 'filesystem', 'ci', 'permissions', 'secrets', 'network')
$seen = @{}
$count = 0

foreach ($c in @($cap.capabilities)) {
    $count++
    $id = [string]$c.id
    if ([string]::IsNullOrWhiteSpace($id)) { Fail "capability #$count has empty id"; continue }
    if ($id -notmatch '^os\.[a-z0-9]+([-.][a-z0-9]+)*$') { Fail "$id has invalid id format" }
    if ($seen.ContainsKey($id)) { Fail "duplicate capability id $id" }
    $seen[$id] = $true

    if ([string]::IsNullOrWhiteSpace([string]$c.title)) { Fail "$id missing title" }
    if ([string]::IsNullOrWhiteSpace([string]$c.intent)) { Fail "$id missing intent" }

    $skill = [string]$c.skill
    if (-not $skillNames.ContainsKey($skill)) { Fail "$id references unknown skill '$skill'" }

    $risk = [string]$c.risk
    if ($allowedRisk -notcontains $risk) { Fail "$id has invalid risk '$risk'" }

    $cost = [string]$c.cost
    if ($allowedCost -notcontains $cost) { Fail "$id has invalid cost '$cost'" }

    $tags = @($c.tags | ForEach-Object { [string]$_ })
    if ($tags.Count -eq 0) { Fail "$id must declare at least one tag" }
    foreach ($tag in $tags) {
        if ($tag -notmatch '^[a-z0-9][a-z0-9-]*$') { Fail "$id has invalid tag '$tag'" }
    }

    Test-SafeCommand -Command ([string]$c.entrypoint) -Field "$id.entrypoint"
    foreach ($v in @($c.validations)) { Test-SafeCommand -Command ([string]$v) -Field "$id.validations" }

    foreach ($doc in @($c.docs | ForEach-Object { [string]$_ })) {
        if (-not $docIds.ContainsKey($doc)) { Fail "$id references unknown docs-index section '$doc'" }
    }

    $needsApproval = ($risk -in @('high', 'critical')) -or (@($tags | Where-Object { $criticalTags -contains $_ }).Count -gt 0)
    $hasApproval = ($c.PSObject.Properties.Name -contains 'requiresHumanApproval') -and ([bool]$c.requiresHumanApproval)
    if ($needsApproval -and -not $hasApproval) {
        Fail "$id touches high-risk surface but does not require human approval"
    }

    Write-Host "OK:  $id ($risk/$cost)"
}

if ($count -lt 6) { Fail "expected at least 6 capabilities, found $count" }

$requiredRouteIds = @(
    'route.release',
    'route.incident',
    'route.migration',
    'route.bootstrap',
    'route.docs-audit',
    'route.adapter-drift',
    'route.skill-authoring',
    'route.strict-validation',
    'route.security-review'
)

$allowedMode = @('read-only', 'standard', 'strict', 'controlled-change', 'break-glass', 'release-gate')
$allowedApproval = @('none', 'peer', 'maintainer', 'security', 'incident-command')
$routeSeen = @{}
$routeCount = 0

Write-Host ''
Write-Host '--- capability-manifest routes ---'

foreach ($r in @($routesDoc.routes)) {
    $routeCount++
    $rid = [string]$r.id
    if ($rid -notmatch '^route\.[a-z0-9]+(-[a-z0-9]+)*$') { Fail "route #$routeCount has invalid id '$rid'"; continue }
    if ($routeSeen.ContainsKey($rid)) { Fail "duplicate route id $rid" }
    $routeSeen[$rid] = $true

    if ([string]::IsNullOrWhiteSpace([string]$r.title)) { Fail "$rid missing title" }
    if ([string]::IsNullOrWhiteSpace([string]$r.summary)) { Fail "$rid missing summary" }

    $mode = [string]$r.operatingMode
    if ($allowedMode -notcontains $mode) { Fail "$rid invalid operatingMode '$mode'" }

    $rk = [string]$r.riskLevel
    if ($allowedRisk -notcontains $rk) { Fail "$rid invalid riskLevel '$rk'" }

    $ap = [string]$r.requiredApproval
    if ($allowedApproval -notcontains $ap) { Fail "$rid invalid requiredApproval '$ap'" }

    $rtags = @($r.tags | ForEach-Object { [string]$_ })
    if ($rtags.Count -eq 0) { Fail "$rid must declare at least one tag" }
    foreach ($tag in $rtags) {
        if ($tag -notmatch '^[a-z0-9][a-z0-9-]*$') { Fail "$rid has invalid tag '$tag'" }
    }

    foreach ($sk in @($r.relevantSkills | ForEach-Object { [string]$_ })) {
        if (-not $skillNames.ContainsKey($sk)) { Fail "$rid references unknown skill '$sk'" }
    }

    foreach ($pb in @($r.relevantPlaybooks | ForEach-Object { [string]$_ })) {
        if (-not $playbookIds.ContainsKey($pb)) { Fail "$rid references unknown playbook id '$pb'" }
    }

    foreach ($doc in @($r.docs | ForEach-Object { [string]$_ })) {
        if (-not $docIds.ContainsKey($doc)) { Fail "$rid references unknown docs-index section '$doc'" }
    }

    foreach ($v in @($r.validators)) { Test-SafeCommand -Command ([string]$v) -Field "$rid.validators" }

    $highRisk = ($rk -in @('high', 'critical')) -or (@($rtags | Where-Object { $criticalTags -contains $_ }).Count -gt 0)
    if ($highRisk -and $ap -eq 'none') {
        Fail "$rid is high/critical or critical-tagged but requiredApproval is none"
    }

    Write-Host "OK:  $rid ($mode / $rk / approval=$ap)"
}

foreach ($req in $requiredRouteIds) {
    if (-not $routeSeen.ContainsKey($req)) { Fail "missing required intent route: $req" }
}

if ($routeCount -lt $requiredRouteIds.Count) {
    Fail "expected at least $($requiredRouteIds.Count) routes, found $routeCount"
}

if ($failed) { throw 'Capability registry verification failed.' }

Write-Host ''
Write-Host "Capability checks passed ($count capabilities, $routeCount intent routes)."
