# workflow-status.ps1 — Cheap progressive workflow gate/status view
# Run from repo root or project root:
#   pwsh ./tools/workflow-status.ps1
#   pwsh ./.claude/scripts/workflow-status.ps1
# Optional:
#   pwsh ./tools/workflow-status.ps1 -Phase verify -Json

param(
    [string]$Phase = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

function Resolve-WorkflowManifestPath {
    $candidates = @(
        (Join-Path $Root 'workflow-manifest.json'),
        (Join-Path $Root '.claude/workflow-manifest.json'),
        (Join-Path (Split-Path $Root -Parent) '.claude/workflow-manifest.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'workflow-manifest.json not found. Run from claude-operating-system or a bootstrapped project.'
}

function Read-JsonFile {
    param([string]$Path)
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "Invalid JSON: $Path" }
}

function Get-ArtifactStatus {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'missing' }
    if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') { return 'unsafe' }
    $full = Join-Path (Split-Path (Resolve-WorkflowManifestPath) -Parent) $Path
    if (Test-Path -LiteralPath $full) { return 'present' }
    return 'missing'
}

$manifestPath = Resolve-WorkflowManifestPath
$workflow = Read-JsonFile -Path $manifestPath
$phases = @($workflow.phases)

if ($Phase) {
    $phases = @($phases | Where-Object { [string]$_.id -eq $Phase })
    if ($phases.Count -eq 0) { throw "Unknown workflow phase: $Phase" }
}

$phaseViews = foreach ($phase in $phases) {
    [pscustomobject]@{
        id = [string]$phase.id
        title = [string]$phase.title
        purpose = [string]$phase.purpose
        recommendedCapability = [string]$phase.recommendedCapability
        requiredArtifacts = @($phase.requiredArtifacts | ForEach-Object { [string]$_ })
        gate = [string]$phase.gate
    }
}

$artifactViews = foreach ($path in @($workflow.artifactFirstPaths | ForEach-Object { [string]$_ })) {
    [pscustomobject]@{
        path = $path
        status = Get-ArtifactStatus -Path $path
    }
}

$missing = @($artifactViews | Where-Object { $_.status -ne 'present' })
$result = [pscustomobject]@{
    manifest = $manifestPath
    phaseCount = $phaseViews.Count
    missingArtifactCount = $missing.Count
    phases = $phaseViews
    artifactFirstPaths = $artifactViews
    globalRules = @($workflow.globalRules | ForEach-Object { [string]$_ })
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host 'Claude OS workflow status'
Write-Host "Manifest: $manifestPath"
Write-Host ''
Write-Host 'Phases:'
foreach ($p in $phaseViews) {
    Write-Host ""
    Write-Host "[$($p.id)] $($p.title)"
    Write-Host "  purpose : $($p.purpose)"
    Write-Host "  route   : $($p.recommendedCapability)"
    Write-Host "  gate    : $($p.gate)"
    Write-Host "  outputs : $(@($p.requiredArtifacts) -join ', ')"
}
Write-Host ''
Write-Host 'Artifact-first paths:'
foreach ($a in $artifactViews) {
    Write-Host "  $($a.status.ToUpper().PadRight(7)) $($a.path)"
}
Write-Host ''
Write-Host "Workflow phases: $($phaseViews.Count), missing/unsafe artifacts: $($missing.Count)"
if ($missing.Count -gt 0) {
    Write-Host 'Next action: create or refresh missing artifact-first files before relying on chat memory.'
}
