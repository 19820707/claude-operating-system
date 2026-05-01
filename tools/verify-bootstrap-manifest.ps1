# verify-bootstrap-manifest.ps1 — Fail if template tree drifts from bootstrap-manifest.json
# Run from repo root or any cwd (uses script location):
#   pwsh ./tools/verify-bootstrap-manifest.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $RepoRoot "bootstrap-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "bootstrap-manifest.json not found at $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$failed = $false

function Test-DirCount {
    param(
        [string]$RelativePath,
        [string]$Include,
        [int]$Exact = -1,
        [int]$Minimum = -1
    )
    $full = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "FAIL: missing directory $full"
        return $false
    }
    $n = (Get-ChildItem -LiteralPath $full -Filter $Include -File).Count
    if ($Exact -ge 0 -and $n -ne $Exact) {
        Write-Host "FAIL: $RelativePath — expected exactly $Exact $Include files, found $n"
        return $false
    }
    if ($Minimum -ge 0 -and $n -lt $Minimum) {
        Write-Host "FAIL: $RelativePath — expected at least $Minimum $Include files, found $n"
        return $false
    }
    Write-Host "OK:  $RelativePath ($n $Include)"
    return $true
}

Write-Host "verify-bootstrap-manifest"
Write-Host "Repo    : $RepoRoot"
Write-Host "Manifest: $manifestPath"
Write-Host ""

foreach ($prop in $manifest.repoIntegrity.PSObject.Properties) {
    $rel = $prop.Name
    $rule = $prop.Value
    $inc = [string]$rule.include
    if ($rule.PSObject.Properties.Name -contains 'exact') {
        if (-not (Test-DirCount -RelativePath $rel -Include $inc -Exact ([int]$rule.exact))) { $failed = $true }
    } elseif ($rule.PSObject.Properties.Name -contains 'minimum') {
        if (-not (Test-DirCount -RelativePath $rel -Include $inc -Minimum ([int]$rule.minimum))) { $failed = $true }
    } else {
        Write-Host "FAIL: rule for $rel has neither exact nor minimum"
        $failed = $true
    }
}

if ($failed) {
    throw "Manifest verification failed. Update templates or bootstrap-manifest.json."
}

Write-Host ""
Write-Host "All repoIntegrity checks passed."
