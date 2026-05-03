# verify-agent-adapters.ps1 — Multi-agent adapter templates + agent-adapters-manifest (read-only)
#   pwsh ./tools/verify-agent-adapters.ps1
#   pwsh ./tools/verify-agent-adapters.ps1 -Json

param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
$script:AdapterFails = [System.Collections.Generic.List[string]]::new()

function Fail {
    param([string]$Message)
    $msg = Redact-SensitiveText -Text $Message -MaxLength 400
    [void]$script:AdapterFails.Add($msg)
    if (-not $Json) {
        Write-Host "FAIL: $msg"
    }
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

if (-not $Json) {
    Write-Host 'verify-agent-adapters'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
}

$adapterDir = Join-Path $RepoRoot 'templates/adapters'
foreach ($name in @(
        'AGENTS.md',
        'cursor-claude-os-runtime.mdc',
        'agent-runtime.md',
        'agent-handoff.md',
        'agent-operating-contract.md',
        'agents-OPERATING_CONTRACT.md'
    )) {
    if (-not (Test-Path -LiteralPath (Join-Path $adapterDir $name))) {
        Fail "missing template: templates/adapters/$name"
    }
}

Require-ContainsLiteral -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' `
    -Substring 'description: Use Claude OS Runtime for governed engineering work' `
    -Why 'Cursor rule frontmatter must use required description line'
Require-Contains -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' -Pattern 'alwaysApply:\s*true' `
    -Why 'Cursor rule must set alwaysApply: true'
Require-ContainsLiteral -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' `
    -Substring 'CLAUDE.md' -Why 'Cursor rule must mention CLAUDE.md'
Require-ContainsLiteral -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' `
    -Substring '.claude/session-state.md' -Why 'Cursor rule must mention session-state'
Require-ContainsLiteral -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' `
    -Substring '.claude/workflow-manifest.json' -Why 'Cursor rule must mention workflow-manifest'
Require-ContainsLiteral -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' `
    -Substring '.claude/os-capabilities.json' -Why 'Cursor rule must mention os-capabilities'
Require-ContainsLiteral -RelativePath 'templates/adapters/cursor-claude-os-runtime.mdc' `
    -Substring '.claude/capability-manifest.json' -Why 'Cursor rule must mention capability-manifest'

Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'Claude OS Runtime' `
    -Why 'AGENTS.md must state Claude OS Runtime'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'CLAUDE.md' `
    -Why 'AGENTS.md must mention CLAUDE.md'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring '.claude/session-state.md' `
    -Why 'AGENTS.md must mention session-state'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring '.claude/workflow-manifest.json' `
    -Why 'AGENTS.md must mention workflow-manifest'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring '.claude/os-capabilities.json' `
    -Why 'AGENTS.md must mention os-capabilities'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring '.claude/capability-manifest.json' `
    -Why 'AGENTS.md must mention capability-manifest'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'session-prime.ps1' `
    -Why 'AGENTS.md must mention session-prime script'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'route-capability.ps1' `
    -Why 'AGENTS.md must mention route-capability script'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'workflow-status.ps1' `
    -Why 'AGENTS.md must mention workflow-status script'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'session-digest.ps1' `
    -Why 'AGENTS.md must mention session-digest script'
Require-Contains -RelativePath 'templates/adapters/AGENTS.md' -Pattern 'human approval required' `
    -Why 'AGENTS.md must mention human approval required'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'git add .' `
    -Why 'AGENTS.md must forbid git add .'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'git push --force' `
    -Why 'AGENTS.md must forbid git push --force'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'git reset --hard' `
    -Why 'AGENTS.md must forbid git reset --hard'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'git stash pop' `
    -Why 'AGENTS.md must mention git stash pop caution'
Require-ContainsLiteral -RelativePath 'templates/adapters/AGENTS.md' -Substring 'PII' `
    -Why 'AGENTS.md must warn on PII / sensitive output'

foreach ($tok in @('session-prime', 'session-absorb', 'session-digest')) {
    Require-ContainsLiteral -RelativePath 'templates/adapters/agent-handoff.md' -Substring $tok `
        -Why "agent-handoff.md must mention $tok"
}

Require-ContainsLiteral -RelativePath 'templates/adapters/agent-operating-contract.md' -Substring 'git add .' `
    -Why 'operating-contract must mention git add .'
Require-ContainsLiteral -RelativePath 'templates/adapters/agent-operating-contract.md' -Substring 'git push --force' `
    -Why 'operating-contract must mention git push --force'

Require-ContainsLiteral -RelativePath 'templates/adapters/agents-OPERATING_CONTRACT.md' -Substring '.agent/operating-contract.md' `
    -Why 'legacy .agents stub must point at canonical .agent/operating-contract.md'

Require-File 'agent-adapters-manifest.json'
Require-File 'schemas/agent-adapters.schema.json'

$manPath = Join-Path $RepoRoot 'agent-adapters-manifest.json'
$doc = Get-Content -LiteralPath $manPath -Raw | ConvertFrom-Json
if ([int]$doc.schemaVersion -lt 1) { Fail 'agent-adapters-manifest.json: invalid schemaVersion' }

$expectedSingle = @{
    'claude-code' = @{ entry = 'CLAUDE.md'; path = '.claude/'; managed = $false }
    'cursor'      = @{ entry = '.cursor/rules/claude-os-runtime.mdc'; path = '.claude/'; managed = $true }
    'codex'       = @{ entry = 'AGENTS.md'; path = '.claude/'; managed = $false }
}
$expectedMulti = @{
    'neutral-agent-docs' = @{
        paths = @(
            '.agent/runtime.md',
            '.agent/handoff.md',
            '.agent/operating-contract.md',
            '.agents/OPERATING_CONTRACT.md'
        )
        path  = '.claude/'
        managed = $true
    }
}

$ids = @{}
foreach ($a in @($doc.adapters)) {
    $id = [string]$a.id
    if ($ids.ContainsKey($id)) { Fail "duplicate adapter id: $id" }
    [void]($ids[$id] = $true)

    $props = $a.PSObject.Properties.Name
    $hasEntry = $props -contains 'entrypoint'
    $hasEntries = $props -contains 'entrypoints'

    if ($hasEntry -and $hasEntries) {
        Fail "adapter $id must not define both entrypoint and entrypoints"
        continue
    }
    if (-not $hasEntry -and -not $hasEntries) {
        Fail "adapter $id missing entrypoint or entrypoints"
        continue
    }

    if ([string]::IsNullOrWhiteSpace([string]$a.runtimePath)) { Fail "adapter $id missing runtimePath"; continue }
    if ($a.PSObject.Properties.Name -notcontains 'managed') { Fail "adapter $id missing managed"; continue }
    if ([string]::IsNullOrWhiteSpace([string]$a.purpose)) { Fail "adapter $id missing purpose"; continue }

    if ($expectedSingle.ContainsKey($id)) {
        $exp = $expectedSingle[$id]
        if (-not $hasEntry) { Fail "adapter $id expected entrypoint form"; continue }
        if (([string]$a.entrypoint) -ne $exp.entry) {
            Fail "adapter $id entrypoint expected '$($exp.entry)', got '$($a.entrypoint)'"
        }
        if (([string]$a.runtimePath) -ne $exp.path) {
            Fail "adapter $id runtimePath expected '$($exp.path)', got '$($a.runtimePath)'"
        }
        if ([bool]$a.managed -ne [bool]$exp.managed) {
            Fail "adapter $id managed flag mismatch (expected $($exp.managed))"
        }
    } elseif ($expectedMulti.ContainsKey($id)) {
        $exp = $expectedMulti[$id]
        if (-not $hasEntries) { Fail "adapter $id expected entrypoints array"; continue }
        $got = @($a.entrypoints | ForEach-Object { [string]$_ })
        foreach ($p in $exp.paths) {
            if ($got -notcontains $p) { Fail "adapter $id missing entrypoint path: $p" }
        }
        if (([string]$a.runtimePath) -ne $exp.path) {
            Fail "adapter $id runtimePath expected '$($exp.path)', got '$($a.runtimePath)'"
        }
        if ([bool]$a.managed -ne [bool]$exp.managed) {
            Fail "adapter $id managed flag mismatch (expected $($exp.managed))"
        }
    } else {
        Fail "unexpected adapter id: $id"
    }
}

foreach ($k in $expectedSingle.Keys) {
    if (-not $ids.ContainsKey($k)) { Fail "missing adapter id: $k" }
}
foreach ($k in $expectedMulti.Keys) {
    if (-not $ids.ContainsKey($k)) { Fail "missing adapter id: $k" }
}

$status = if ($script:AdapterFails.Count -gt 0) { 'fail' } else { 'ok' }
$result = [ordered]@{
    name     = 'verify-agent-adapters'
    status   = $status
    failures = @($script:AdapterFails)
    repoRoot = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
} elseif ($script:AdapterFails.Count -eq 0) {
    Write-Host 'OK:  templates/adapters (6 files)'
    Write-Host 'OK:  agent-adapters-manifest.json (4 adapters)'
    Write-Host ''
    Write-Host 'Agent adapter checks passed.'
}

if ($script:AdapterFails.Count -gt 0) {
    throw "Agent adapter verification failed: $($script:AdapterFails.Count) issue(s)."
}
