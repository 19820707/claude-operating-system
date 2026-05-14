# verify-token-economy-policy.ps1 — Enforce surgical token economy and no-false-green contracts
#   pwsh ./tools/verify-token-economy-policy.ps1
#   pwsh ./tools/verify-token-economy-policy.ps1 -Json

param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
$script:Fails = [System.Collections.Generic.List[string]]::new()

function Fail {
    param([string]$Message)
    $safe = Redact-SensitiveText -Text $Message -MaxLength 300
    [void]$script:Fails.Add($safe)
    if (-not $Json) { Write-Host "FAIL: $safe" }
}

function Require-File {
    param([string]$RelativePath)
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath))) {
        Fail "missing file: $RelativePath"
    }
}

function Require-ContainsLiteral {
    param([string]$RelativePath, [string]$Substring, [string]$Why)
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { Fail "missing file for content check: $RelativePath"; return }
    $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
    if (-not $raw.Contains($Substring)) { Fail "$Why ($RelativePath)" }
}

function Require-ContainsRegex {
    param([string]$RelativePath, [string]$Pattern, [string]$Why)
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { Fail "missing file for content check: $RelativePath"; return }
    $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
    if ($raw -notmatch $Pattern) { Fail "$Why ($RelativePath)" }
}

if (-not $Json) {
    Write-Host 'verify-token-economy-policy'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
}

foreach ($p in @(
    'policies/token-economy.md',
    'policies/model-selection.md',
    'policies/production-safety.md',
    'source/skills/token-economy/SKILL.md',
    'source/skills/production-safety/SKILL.md',
    'templates/adapters/AGENTS.md',
    'templates/adapters/cursor-claude-os-runtime.mdc',
    'templates/adapters/agent-operating-contract.md',
    'CLAUDE.md'
)) { Require-File $p }

# Surgical token-economy enforcement.
Require-ContainsLiteral 'policies/token-economy.md' 'Default to surgical mode' 'token-economy policy must define default surgical mode'
Require-ContainsLiteral 'policies/token-economy.md' 'Task execution budgets' 'token-economy policy must define task execution budgets'
Require-ContainsLiteral 'policies/token-economy.md' 'sub-agent budget is zero' 'token-economy policy must make sub-agent budget zero for narrow tasks'
Require-ContainsLiteral 'policies/token-economy.md' 'named-file task' 'token-economy policy must protect named-file tasks'
Require-ContainsLiteral 'source/skills/token-economy/SKILL.md' 'Surgical mode is mandatory' 'token-economy skill must enforce surgical mode'
Require-ContainsLiteral 'source/skills/token-economy/SKILL.md' 'Do not use `Explore`' 'token-economy skill must prohibit Explore by default'
Require-ContainsLiteral 'templates/adapters/AGENTS.md' 'Do **not** run broad repository discovery' 'generic AGENTS adapter must prohibit broad discovery'
Require-ContainsLiteral 'templates/adapters/AGENTS.md' 'Do **not** use `Explore` / sub-agents' 'generic AGENTS adapter must gate sub-agents'
Require-ContainsLiteral 'templates/adapters/cursor-claude-os-runtime.mdc' 'do **not** do broad repository discovery' 'Cursor adapter must prohibit broad discovery'
Require-ContainsLiteral 'templates/adapters/cursor-claude-os-runtime.mdc' 'do **not** use sub-agents' 'Cursor adapter must gate sub-agents'
Require-ContainsLiteral 'templates/adapters/agent-operating-contract.md' 'token-proportional execution' 'neutral operating contract must mention token-proportional execution'
Require-ContainsRegex 'CLAUDE.md' 'Delegation gates' 'global CLAUDE.md must define delegation gates'
Require-ContainsRegex 'policies/model-selection.md' 'Delegation gates' 'model selection policy must define delegation gates'
Require-ContainsLiteral 'policies/model-selection.md' 'Open-ended exploration is not allowed' 'model selection policy must forbid open-ended exploration'

# No false green enforcement.
foreach ($p in @('policies/production-safety.md','source/skills/production-safety/SKILL.md','templates/adapters/AGENTS.md','templates/adapters/agent-operating-contract.md')) {
    Require-ContainsLiteral $p 'fallback != healthy' "$p must include fallback != healthy"
    Require-ContainsLiteral $p 'skipped != passed' "$p must include skipped != passed"
    Require-ContainsLiteral $p 'warning != success' "$p must include warning != success"
}

$status = if ($script:Fails.Count -gt 0) { 'fail' } else { 'ok' }
$result = [ordered]@{
    name = 'verify-token-economy-policy'
    status = $status
    failures = @($script:Fails)
    repoRoot = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
} elseif ($script:Fails.Count -eq 0) {
    Write-Host 'OK: token economy policy contracts present'
    Write-Host 'OK: no-false-green policy contracts present'
    Write-Host 'Token economy policy checks passed.'
}

if ($script:Fails.Count -gt 0) {
    throw "Token economy policy verification failed: $($script:Fails.Count) issue(s)."
}
