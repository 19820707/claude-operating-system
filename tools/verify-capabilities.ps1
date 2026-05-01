# verify-capabilities.ps1 — Validate os-capabilities.json routing contract
# Run from repo root or any cwd:
#   pwsh ./tools/verify-capabilities.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$capPath = Join-Path $RepoRoot 'os-capabilities.json'
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

if (-not $cap.capabilities) { throw 'os-capabilities.json missing capabilities array' }

$docIds = @{}
foreach ($section in @($docs.sections)) { $docIds[[string]$section.id] = $true }

$skillNames = @{}
Get-ChildItem -LiteralPath $skillsRoot -Directory | ForEach-Object { $skillNames[$_.Name] = $true }

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

if ($failed) { throw 'Capability registry verification failed.' }

Write-Host ''
Write-Host "Capability registry checks passed ($count capabilities)."
