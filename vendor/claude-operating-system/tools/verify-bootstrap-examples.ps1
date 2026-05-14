# verify-bootstrap-examples.ps1 — Validate examples/project-bootstrap reference trees (paths, JSONL shape, no sensitive patterns)
#   pwsh ./tools/verify-bootstrap-examples.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

$script:Failed = $false

function Write-Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:Failed = $true
}

function Test-NoSensitivePatterns {
    param([string]$RelativePath)
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { return }
    $t = Get-Content -LiteralPath $full -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($t)) { return }
    if ($t -match '(?i)bearer\s+[a-z0-9._~+\-/]{8,}') { Write-Fail "possible bearer token in $RelativePath"; return }
    if ($t -match 'ghp_[A-Za-z0-9_]{10,}') { Write-Fail "possible GitHub PAT in $RelativePath"; return }
    if ($t -match 'github_pat_[A-Za-z0-9_]{10,}') { Write-Fail "possible GitHub fine-grained PAT in $RelativePath"; return }
    if ($t -match 'sk-[A-Za-z0-9]{10,}') { Write-Fail "possible API sk- key in $RelativePath"; return }
    if ($t -match 'AKIA[0-9A-Z]{16}') { Write-Fail "possible AWS key in $RelativePath"; return }
}

function Test-DecisionLogSampleLine {
    param(
        [string]$Line,
        [string]$Context
    )
    $t = $Line.Trim()
    if (-not $t) { return }
    try {
        $o = $t | ConvertFrom-Json
    }
    catch {
        Write-Fail "invalid JSON in $Context : $($_.Exception.Message)"
        return
    }
    foreach ($req in @('id', 'ts', 'type', 'trigger', 'policy_applied', 'decision')) {
        if (-not ($o.PSObject.Properties.Name -contains $req)) {
            Write-Fail "decision log line missing '$req' in $Context"
            return
        }
    }
    $allowedTypes = @(
        'model_selection', 'scope_boundary', 'risk_acceptance', 'invariant_override', 'mode_escalation',
        'approval_gate', 'mode_selection', 'approval', 'other'
    )
    if ([string]$o.type -notin $allowedTypes) {
        Write-Fail "decision log invalid type '$($o.type)' in $Context"
    }
}

Write-Host 'verify-bootstrap-examples'

foreach ($tier in @('minimal', 'advanced')) {
    $root = Join-Path $RepoRoot (Join-Path 'examples/project-bootstrap' $tier)
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Fail "missing example directory: examples/project-bootstrap/$tier"
        continue
    }
    $mfPath = Join-Path $root 'example-manifest.json'
    if (-not (Test-Path -LiteralPath $mfPath)) {
        Write-Fail "missing example-manifest.json in $tier"
        continue
    }
    $mf = Get-Content -LiteralPath $mfPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([int]$mf.schemaVersion -lt 1) { Write-Fail "$tier invalid schemaVersion" }
    foreach ($rel in @($mf.requiredPaths)) {
        $p = Join-Path $root ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Fail "$tier missing required path: $rel"
        }
    }
    $dlRel = [string]$mf.decisionLogSampleRelative
    if (-not [string]::IsNullOrWhiteSpace($dlRel)) {
        $dlFull = Join-Path $root ($dlRel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $dlFull)) {
            Write-Fail "$tier missing decision log sample: $dlRel"
        }
        else {
            $i = 0
            Get-Content -LiteralPath $dlFull -Encoding utf8 | ForEach-Object {
                $i++
                Test-DecisionLogSampleLine -Line $_ -Context "examples/project-bootstrap/$tier ($dlRel line $i)"
            }
        }
    }

    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $relFromTier = $_.FullName.Substring($root.Length).TrimStart([char][System.IO.Path]::DirectorySeparatorChar) -replace '\\', '/'
        $repoRel = "examples/project-bootstrap/$tier/$relFromTier"
        Test-NoSensitivePatterns -RelativePath $repoRel
    }
}

if ($script:Failed) { throw 'Bootstrap example verification failed.' }
Write-Host 'OK:  examples/project-bootstrap (minimal + advanced)'
exit 0
