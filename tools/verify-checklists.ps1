# verify-checklists.ps1 — Validate safety/release checklist gate contracts
# Run from repo root or any cwd:
#   pwsh ./tools/verify-checklists.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Require-Text {
    param(
        [string]$File,
        [string[]]$Terms,
        [string]$Label
    )
    $path = Join-Path $RepoRoot $File
    if (-not (Test-Path -LiteralPath $path)) {
        Fail "$Label missing: $File"
        return
    }
    $content = (Get-Content -LiteralPath $path -Raw).ToLowerInvariant()
    foreach ($term in $Terms) {
        if (-not $content.Contains($term.ToLowerInvariant())) {
            Fail "$Label missing required term '$term'"
        }
    }
    Write-Host "OK:  $Label"
}

Write-Host 'verify-checklists'
Write-Host "Repo: $RepoRoot"
Write-Host ''

# Invariant: critical checklists must keep explicit human approval, rollback, secret/PII, and safe-output gates.
Require-Text -File 'templates/checklists/SECURITY-CHECKLIST.md' -Label 'security checklist' -Terms @(
    'human approval required',
    'rollback',
    'secrets',
    'tokens',
    'PII',
    'fails closed',
    'filesystem writes',
    'Do not paste stack traces'
)

Require-Text -File 'templates/checklists/RELEASE-CHECKLIST.md' -Label 'release checklist' -Terms @(
    'human approval required',
    'rollback',
    'go/no-go',
    'residual risk',
    'acceptance criteria',
    'Security checklist',
    'raw stack traces',
    'PII'
)

if ($failed) { throw 'Checklist verification failed.' }

Write-Host ''
Write-Host 'Checklist checks passed.'
exit 0
