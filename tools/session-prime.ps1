# session-prime.ps1 — Build compact startup context from project artifacts
# Inspired by prime_context: wake the agent with bounded local state.
# Run from a bootstrapped project root:
#   pwsh .claude/scripts/session-prime.ps1
# Or from OS repo with -ProjectPath:
#   pwsh ./tools/session-prime.ps1 -ProjectPath ../my-project

param(
    [string]$ProjectPath = '.',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath($ProjectPath)
$ClaudeDir = Join-Path $Root '.claude'

function Read-TextSafe {
    param([string]$RelativePath, [int]$MaxChars = 4000)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $text = Get-Content -LiteralPath $path -Raw
    if ($text.Length -gt $MaxChars) { return $text.Substring(0, $MaxChars) + "`n...[truncated]" }
    return $text
}

function Read-JsonSafe {
    param([string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

if (-not (Test-Path -LiteralPath $ClaudeDir)) {
    throw '.claude directory not found. Run from a bootstrapped project or pass -ProjectPath.'
}

# Invariant: prime reads bounded artifacts only; it never scans the full repository.
$session = Read-TextSafe -RelativePath '.claude/session-state.md' -MaxChars 3500
$learning = Read-TextSafe -RelativePath '.claude/learning-log.md' -MaxChars 2500
$workflow = Read-JsonSafe -RelativePath '.claude/workflow-manifest.json'
$capabilities = Read-JsonSafe -RelativePath '.claude/os-capabilities.json'

$result = [pscustomobject]@{
    project = $Root
    hasSessionState = [bool]$session
    hasLearningLog = [bool]$learning
    workflowPhases = if ($workflow) { @($workflow.phases | ForEach-Object { $_.id }) } else { @() }
    capabilityCount = if ($capabilities) { @($capabilities.capabilities).Count } else { 0 }
    sessionStateExcerpt = $session
    learningLogExcerpt = $learning
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}

Write-Host 'Claude OS session prime'
Write-Host "Project: $Root"
Write-Host ''
Write-Host '[workflow phases]'
Write-Host "  $($result.workflowPhases -join ' -> ')"
Write-Host ''
Write-Host '[capabilities]'
Write-Host "  count: $($result.capabilityCount)"
Write-Host ''
Write-Host '[session-state excerpt]'
Write-Host $session
Write-Host ''
Write-Host '[learning-log excerpt]'
Write-Host $learning
