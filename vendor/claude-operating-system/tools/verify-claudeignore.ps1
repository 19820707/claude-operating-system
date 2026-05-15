# verify-claudeignore.ps1 — Scope-control template verifier
#   pwsh ./tools/verify-claudeignore.ps1
#   pwsh ./tools/verify-claudeignore.ps1 -Json

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
    Write-Host 'verify-claudeignore'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
}

Require-ContainsLiteral 'templates/claudeignore' '.env*' 'claudeignore must exclude env files'
Require-ContainsLiteral 'templates/claudeignore' '*.pem' 'claudeignore must exclude private key material'
Require-ContainsLiteral 'templates/claudeignore' 'secrets/' 'claudeignore must exclude secrets directory'
Require-ContainsLiteral 'templates/claudeignore' 'credentials/' 'claudeignore must exclude credentials directory'
Require-ContainsLiteral 'templates/claudeignore' 'node_modules/' 'claudeignore must exclude dependencies'
Require-ContainsLiteral 'templates/claudeignore' 'dist/' 'claudeignore must exclude build output'
Require-ContainsLiteral 'templates/claudeignore' 'coverage/' 'claudeignore must exclude coverage output'
Require-ContainsLiteral 'templates/claudeignore' 'reports/' 'claudeignore must exclude generated reports'
Require-ContainsLiteral 'templates/claudeignore' 'graphify-out/cache/' 'claudeignore must exclude graph cache'
Require-ContainsLiteral 'policies/scope-control.md' '.claudeignore' 'scope-control policy must document .claudeignore'
Require-ContainsLiteral 'policies/scope-control.md' 'human approval required' 'scope-control policy must preserve critical surface approval gate'
Require-ContainsLiteral 'SECURITY.md' '.claudeignore' 'security model must mention .claudeignore scope control'

$status = if ($script:Fails.Count -gt 0) { 'fail' } else { 'ok' }
$result = [ordered]@{
    name = 'verify-claudeignore'
    status = $status
    failures = @($script:Fails)
    repoRoot = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6 -Compress | Write-Output
} elseif ($script:Fails.Count -eq 0) {
    Write-Host 'OK: .claudeignore template and scope-control policy present'
    Write-Host 'Claudeignore checks passed.'
}

if ($script:Fails.Count -gt 0) {
    throw "Claudeignore verification failed: $($script:Fails.Count) issue(s)."
}
