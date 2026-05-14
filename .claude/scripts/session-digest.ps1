# session-digest.ps1 — Append an end-of-session digest to decision log and learning log
# Inspired by digest: close work with outcome, validation, risks, and next action.
# Run from a bootstrapped project root:
#   pwsh .claude/scripts/session-digest.ps1 -Summary "Implemented router" -Outcome passed -Next "Run health"

param(
    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [string]$Outcome = 'unknown',
    [string]$Validation = '',
    [string]$Risks = '',
    [string]$Next = '',
    [string]$ProjectPath = '.',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath($ProjectPath)
$ClaudeDir = Join-Path $Root '.claude'
$LearningPath = Join-Path $ClaudeDir 'learning-log.md'
$DecisionPath = Join-Path $ClaudeDir 'decision-log.jsonl'

if (-not (Test-Path -LiteralPath $ClaudeDir)) {
    throw '.claude directory not found. Run from a bootstrapped project or pass -ProjectPath.'
}
if ([string]::IsNullOrWhiteSpace($Summary)) { throw 'Summary cannot be empty.' }
if ($Summary.Length -gt 1200) { throw 'Summary is too long; keep digest summary under 1200 characters.' }
if ($Outcome -notmatch '^[a-z0-9][a-z0-9-]{0,40}$') { throw 'Outcome must be a short slug.' }

$stamp = (Get-Date).ToUniversalTime().ToString('o')
$record = [pscustomobject]@{
    ts = $stamp
    type = 'session-digest'
    summary = $Summary.Trim()
    outcome = $Outcome
    validation = $Validation.Trim()
    risks = $Risks.Trim()
    next = $Next.Trim()
}

$markdown = @"

## Digest — $stamp

- outcome: $Outcome
- summary: $($Summary.Trim())
- validation: $($Validation.Trim())
- risks: $($Risks.Trim())
- next: $($Next.Trim())
"@

# Invariant: digest records handoff facts; it does not infer hidden state or dump raw tool output.
if ($DryRun) {
    $record | ConvertTo-Json -Depth 4 -Compress | Write-Output
    Write-Host $markdown
    exit 0
}

if (-not (Test-Path -LiteralPath $LearningPath)) { New-Item -ItemType File -Path $LearningPath -Force | Out-Null }
if (-not (Test-Path -LiteralPath $DecisionPath)) { New-Item -ItemType File -Path $DecisionPath -Force | Out-Null }
Add-Content -LiteralPath $LearningPath -Value $markdown -Encoding utf8
Add-Content -LiteralPath $DecisionPath -Value (($record | ConvertTo-Json -Compress -Depth 4)) -Encoding utf8
Write-Host 'Session digest recorded in .claude/learning-log.md and .claude/decision-log.jsonl'
