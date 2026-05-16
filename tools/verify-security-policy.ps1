# verify-security-policy.ps1 — Critical-systems security/no-false-green policy verifier
#   pwsh ./tools/verify-security-policy.ps1
#   pwsh ./tools/verify-security-policy.ps1 -Json

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

function Require-ContainsLiteral {
    param([string]$RelativePath, [string]$Substring, [string]$Why)
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { Fail "missing file: $RelativePath"; return }
    $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8
    if (-not $raw.Contains($Substring)) { Fail "$Why ($RelativePath)" }
}

if (-not $Json) {
    Write-Host 'verify-security-policy'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
}

foreach ($p in @('SECURITY.md', 'policies/production-safety.md', 'source/skills/production-safety/SKILL.md', 'templates/adapters/AGENTS.md', 'templates/adapters/agent-operating-contract.md')) {
    Require-ContainsLiteral $p 'human approval required' "$p must preserve human approval gate"
}

Require-ContainsLiteral 'SECURITY.md' 'Threat model' 'SECURITY.md must define threat model'
Require-ContainsLiteral 'SECURITY.md' 'Prompt injection' 'SECURITY.md must cover prompt injection'
Require-ContainsLiteral 'SECURITY.md' 'Secret exfiltration' 'SECURITY.md must cover secret exfiltration'
Require-ContainsLiteral 'SECURITY.md' 'Cross-project contamination' 'SECURITY.md must cover cross-project contamination'
Require-ContainsLiteral 'SECURITY.md' 'Adapter drift' 'SECURITY.md must cover adapter drift'
Require-ContainsLiteral 'SECURITY.md' 'Output hygiene' 'SECURITY.md must define output hygiene'

foreach ($p in @('SECURITY.md', 'policies/production-safety.md', 'source/skills/production-safety/SKILL.md', 'templates/adapters/AGENTS.md', 'templates/adapters/agent-operating-contract.md')) {
    Require-ContainsLiteral $p 'fallback != healthy' "$p must include fallback != healthy"
    Require-ContainsLiteral $p 'skipped != passed' "$p must include skipped != passed"
    Require-ContainsLiteral $p 'warning != success' "$p must include warning != success"
}

$status = if ($script:Fails.Count -gt 0) { 'fail' } else { 'ok' }
$result = [ordered]@{
    name = 'verify-security-policy'
    status = $status
    failures = @($script:Fails)
    repoRoot = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
} elseif ($script:Fails.Count -eq 0) {
    Write-Host 'OK: security threat model and no-false-green contracts present'
    Write-Host 'Security policy checks passed.'
}

if ($script:Fails.Count -gt 0) {
    throw "Security policy verification failed: $($script:Fails.Count) issue(s)."
}
exit 0
