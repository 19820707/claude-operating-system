# verify-grounding.ps1 — Grounding Verification Engine wrapper
# Runs the formal proof obligation engine and reports composite grounding score.
# Score = Coverage x Accuracy x (1 - Staleness); threshold 0.6 = grounding gap.
#
# Usage:
#   pwsh ./tools/verify-grounding.ps1
#   pwsh ./tools/verify-grounding.ps1 -Mode auto-generate
#   pwsh ./tools/verify-grounding.ps1 -Mode assert --Id GRND-001 --Claim "..." --Type file_exists --Path tools/foo.ps1
#   pwsh ./tools/verify-grounding.ps1 -Mode score   # machine-readable score only
#   pwsh ./tools/verify-grounding.ps1 -Json

param(
    [ValidateSet('verify', 'auto-generate', 'assert', 'report', 'score', 'contradiction-resolve')]
    [string]$Mode = 'report',
    [switch]$Json,
    [switch]$AutoGenerateFirst,
    [string]$Id = '',
    [string]$Claim = '',
    [string]$Type = '',
    [string]$Path = '',
    [string]$Glob = '',
    [string]$Pattern = '',
    [string]$Command = '',
    [string]$Expected = '',
    [string]$InvariantId = '',
    [double]$Confidence = 0.8,
    [double]$DecayHours = 48.0,
    [string[]]$Tags = @()
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$Checks = [System.Collections.Generic.List[object]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()
$Failures = [System.Collections.Generic.List[string]]::new()
$Findings = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    [void]$script:Checks.Add([pscustomobject]@{
        name   = $Name
        status = $Status
        note   = $Detail
    })
}

# ── Node.js prerequisite ──────────────────────────────────────────────────────

$nodePath = (Get-Command node -ErrorAction SilentlyContinue)?.Source
if (-not $nodePath) {
    $sw.Stop()
    Add-Check -Name 'node-available' -Status 'skip' -Detail 'node.js not found in PATH — skipping grounding engine'
    $envelope = New-OsValidatorEnvelope -Tool 'verify-grounding' -Status 'skip' `
        -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($Checks) -Warnings @($Warnings) `
        -Failures @($Failures) -Findings @($Findings)
    if ($Json) { $envelope | ConvertTo-Json -Depth 8 -Compress | Write-Output } else { Write-Host 'skip: node.js not available' }
    exit 0
}

$EngineFile = Join-Path $RepoRoot 'tools/dist/grounding-engine.cjs'
if (-not (Test-Path $EngineFile)) {
    $sw.Stop()
    Add-Check -Name 'engine-bundle' -Status 'fail' -Detail 'tools/dist/grounding-engine.cjs not found — rebuild needed'
    [void]$script:Failures.Add('engine-bundle-missing')
    $envelope = New-OsValidatorEnvelope -Tool 'verify-grounding' -Status 'fail' `
        -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($Checks) -Warnings @($Warnings) `
        -Failures @($Failures) -Findings @($Findings)
    if ($Json) { $envelope | ConvertTo-Json -Depth 8 -Compress | Write-Output } else { Write-Host 'FAIL: grounding-engine.cjs missing' }
    exit 1
}
Add-Check -Name 'engine-bundle' -Status 'ok' -Detail $EngineFile

# ── Auto-generate before verify if requested ──────────────────────────────────

if ($AutoGenerateFirst -or $Mode -eq 'verify') {
    $agResult = & node $EngineFile $RepoRoot auto-generate 2>&1
    if ($LASTEXITCODE -ne 0) {
        [void]$script:Warnings.Add("auto-generate returned $LASTEXITCODE")
    }
    if (-not $Json) { $agResult | Write-Host }
    Add-Check -Name 'auto-generate' -Status 'ok' -Detail 'assertions refreshed from OS artifacts'
}

# ── Build node args ───────────────────────────────────────────────────────────

$nodeArgs = @($EngineFile, $RepoRoot, $Mode)

if ($Mode -eq 'assert') {
    if ($Id)         { $nodeArgs += @('--id',           $Id) }
    if ($Claim)      { $nodeArgs += @('--claim',        $Claim) }
    if ($Type)       { $nodeArgs += @('--type',         $Type) }
    if ($Path)       { $nodeArgs += @('--path',         $Path) }
    if ($Glob)       { $nodeArgs += @('--glob',         $Glob) }
    if ($Pattern)    { $nodeArgs += @('--pattern',      $Pattern) }
    if ($Command)    { $nodeArgs += @('--command',      $Command) }
    if ($Expected)   { $nodeArgs += @('--expected',     $Expected) }
    if ($InvariantId){ $nodeArgs += @('--invariant-id', $InvariantId) }
    $nodeArgs += @('--confidence', [string]$Confidence)
    $nodeArgs += @('--decay-hours', [string]$DecayHours)
    if ($Tags.Count -gt 0) { $nodeArgs += @('--tags', ($Tags -join ',')) }
}

# ── Run engine ────────────────────────────────────────────────────────────────

$engineSw = [System.Diagnostics.Stopwatch]::StartNew()
$engineOutput = & node @nodeArgs 2>&1
$engineExit = $LASTEXITCODE
$engineSw.Stop()

$engineText = ($engineOutput | Out-String).Trim()
if (-not $Json) { Write-Host $engineText }

if ($engineExit -ne 0) {
    [void]$script:Failures.Add("grounding-engine-${Mode} exited ${engineExit}")
    Add-Check -Name "engine-${Mode}" -Status 'fail' -Detail "exit $engineExit"
} else {
    Add-Check -Name "engine-${Mode}" -Status 'ok' -Detail "$($engineSw.ElapsedMilliseconds) ms"
}

# ── Parse composite score for envelope ───────────────────────────────────────

$score = $null
$gapDeclared = $false
if ($Mode -in @('verify', 'report', 'score')) {
    $scoreRaw = & node $EngineFile $RepoRoot score 2>&1
    if ($LASTEXITCODE -eq 0) {
        $score = [double]($scoreRaw | Select-Object -Last 1)
        $gapDeclared = $score -lt 0.6
        if ($gapDeclared) {
            [void]$script:Warnings.Add("grounding gap: score=${score} < 0.6")
        }
    }
}

$sw.Stop()
$finalStatus = if ($Failures.Count -gt 0) { 'fail' }
               elseif ($Warnings.Count -gt 0) { 'warn' }
               else { 'ok' }

if ($score -ne $null) {
    [void]$Findings.Add([pscustomobject]@{
        metric   = 'composite_score'
        value    = $score
        grade    = if ($score -ge 0.85) { 'A' } elseif ($score -ge 0.70) { 'B' } elseif ($score -ge 0.60) { 'C' } elseif ($score -ge 0.45) { 'D' } else { 'F' }
        gap      = $gapDeclared
        threshold = 0.6
    })
}

$envelope = New-OsValidatorEnvelope -Tool 'verify-grounding' -Status $finalStatus `
    -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($Checks) `
    -Warnings @($Warnings) -Failures @($Failures) -Findings @($Findings)

if ($Json) { $envelope | ConvertTo-Json -Depth 8 -Compress | Write-Output }

exit 0
