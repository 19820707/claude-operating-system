# verify-agent-adapters.ps1 — Multi-agent adapter templates + agent-adapters-manifest contract
# Run from repo root or any cwd:
#   pwsh ./tools/verify-agent-adapters.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Require-File {
    param([string]$RelativePath)
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Fail "missing file: $RelativePath"
    }
}

function Require-Contains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Why
    )
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Fail "missing file for content check: $RelativePath"
        return
    }
    $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
    if ($raw -notmatch $Pattern) {
        Fail "$Why ($RelativePath)"
    }
}

function Require-ContainsLiteral {
    param(
        [string]$RelativePath,
        [string]$Substring,
        [string]$Why
    )
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Fail "missing file for content check: $RelativePath"
        return
    }
    $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
    if (-not $raw.Contains($Substring)) {
        Fail "$Why ($RelativePath)"
    }
}

Write-Host 'verify-agent-adapters'
Write-Host "Repo: $RepoRoot"
Write-Host ''

$adapterDir = Join-Path $RepoRoot 'templates/adapters'
foreach ($name in @(
        'AGENTS.md',
        'cursor-claude-os-runtime.mdc',
        'agent-runtime.md',
        'agent-handoff.md',
        'agent-operating-contract.md'
    )) {
    if (-not (Test-Path -LiteralPath (Join-Path $adapterDir $name))) {
        Fail "missing template: templates/adapters/$name"
    }
}

Require-Contains -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' -Pattern 'alwaysApply:\s*true' `
    -Why 'Cursor rule must set alwaysApply: true in frontmatter'
Require-Contains -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' -Pattern '\.claude/os-capabilities\.json' `
    -Why 'Cursor rule must reference .claude/os-capabilities.json'
Require-Contains -RelativePath 'templates/adapters/AGENTS.md' -Pattern '\.claude/session-state\.md' `
    -Why 'AGENTS.md must reference .claude/session-state.md'
Require-Contains -RelativePath 'templates/adapters/AGENTS.md' -Pattern 'human approval required' `
    -Why 'AGENTS.md must state human approval required'
foreach ($tok in @('session-prime', 'session-absorb', 'session-digest')) {
    Require-ContainsLiteral -RelativePath 'templates/adapters/agent-handoff.md' -Substring $tok -Why "agent-handoff.md must mention $tok"
}
Require-Contains -RelativePath 'templates/adapters/agent-operating-contract.md' -Pattern 'git add \.' `
    -Why 'operating-contract must prohibit git add .'

Require-File 'agent-adapters-manifest.json'
Require-File 'schemas/agent-adapters-manifest.schema.json'

$manPath = Join-Path $RepoRoot 'agent-adapters-manifest.json'
$doc = Get-Content -LiteralPath $manPath -Raw | ConvertFrom-Json
if ([int]$doc.schemaVersion -lt 1) { Fail 'agent-adapters-manifest.json: invalid schemaVersion' }
$ids = @{}
$expected = @{
    'claude-code' = @{ entry = 'CLAUDE.md'; runtime = '.claude/' }
    'cursor'      = @{ entry = '.cursor/rules/claude-os-runtime.mdc'; runtime = '.claude/' }
    'codex'       = @{ entry = 'AGENTS.md'; runtime = '.claude/' }
}
foreach ($a in @($doc.adapters)) {
    $id = [string]$a.id
    if ($ids.ContainsKey($id)) { Fail "duplicate adapter id: $id" }
    [void]($ids[$id] = $true)
    if (-not $expected.ContainsKey($id)) {
        Fail "unexpected adapter id (allowed: claude-code, cursor, codex): $id"
        continue
    }
    $exp = $expected[$id]
    if (([string]$a.entrypoint) -ne $exp.entry) {
        Fail "adapter $id entrypoint expected '$($exp.entry)', got '$($a.entrypoint)'"
    }
    if (([string]$a.runtime) -ne $exp.runtime) {
        Fail "adapter $id runtime expected '$($exp.runtime)', got '$($a.runtime)'"
    }
    if ([string]::IsNullOrWhiteSpace([string]$a.role)) { Fail "adapter $id missing role" }
}
foreach ($reqId in $expected.Keys) {
    if (-not $ids.ContainsKey($reqId)) { Fail "missing adapter id: $reqId" }
}

if ($failed) { throw 'Agent adapter verification failed.' }

Write-Host 'OK:  templates/adapters (5 files)'
Write-Host 'OK:  agent-adapters-manifest.json (3 adapters)'
Write-Host ''
Write-Host 'Agent adapter checks passed.'
