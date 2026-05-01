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

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Test-RelativeManifestPath {
    param(
        [string]$Path,
        [string]$Field
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail "empty path in $Field"
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        Fail "unsafe relative path '$Path' in $Field"
        return $null
    }
    return ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Test-UniqueManifestList {
    param(
        [object[]]$Values,
        [string]$Field
    )
    if (-not $Values -or $Values.Count -eq 0) {
        Fail "$Field is empty or missing"
        return @()
    }

    $seen = @{}
    $safe = @()
    foreach ($value in $Values) {
        $rel = Test-RelativeManifestPath -Path ([string]$value) -Field $Field
        if (-not $rel) { continue }
        if ($seen.ContainsKey($rel)) {
            Fail "duplicate '$rel' in $Field"
            continue
        }
        $seen[$rel] = $true
        $safe += $rel
    }
    return $safe
}

function Test-DirCount {
    param(
        [string]$RelativePath,
        [string]$Include,
        [int]$Exact = -1,
        [int]$Minimum = -1,
        [bool]$Recursive = $false
    )
    $safeRel = Test-RelativeManifestPath -Path $RelativePath -Field 'repoIntegrity'
    if (-not $safeRel) { return $false }

    $full = Join-Path $RepoRoot $safeRel
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "FAIL: missing directory $safeRel"
        return $false
    }

    $items = if ($Recursive) {
        Get-ChildItem -LiteralPath $full -Filter $Include -File -Recurse
    } else {
        Get-ChildItem -LiteralPath $full -Filter $Include -File
    }
    $n = @($items).Count
    $scope = if ($Recursive) { 'recursive ' } else { '' }

    if ($Exact -ge 0 -and $n -ne $Exact) {
        Write-Host "FAIL: $RelativePath — expected exactly $Exact ${scope}$Include files, found $n"
        return $false
    }
    if ($Minimum -ge 0 -and $n -lt $Minimum) {
        Write-Host "FAIL: $RelativePath — expected at least $Minimum ${scope}$Include files, found $n"
        return $false
    }
    Write-Host "OK:  $RelativePath ($n ${scope}$Include)"
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
    $recursive = ($rule.PSObject.Properties.Name -contains 'recursive') -and ([bool]$rule.recursive)
    if ($rule.PSObject.Properties.Name -contains 'exact') {
        if (-not (Test-DirCount -RelativePath $rel -Include $inc -Exact ([int]$rule.exact) -Recursive $recursive)) { $failed = $true }
    } elseif ($rule.PSObject.Properties.Name -contains 'minimum') {
        if (-not (Test-DirCount -RelativePath $rel -Include $inc -Minimum ([int]$rule.minimum) -Recursive $recursive)) { $failed = $true }
    } else {
        Fail "rule for $rel has neither exact nor minimum"
    }
}

Write-Host ""
Write-Host "projectBootstrap"

if (-not $manifest.projectBootstrap) {
    Fail "missing projectBootstrap section"
} else {
    # Invariant: init-project.ps1 consumes these lists; verifier must reject drift before bootstrap.
    $scriptNames = Test-UniqueManifestList -Values @($manifest.projectBootstrap.scripts) -Field 'projectBootstrap.scripts'
    $criticalPaths = Test-UniqueManifestList -Values @($manifest.projectBootstrap.criticalPaths) -Field 'projectBootstrap.criticalPaths'

    $scriptCountRule = $manifest.repoIntegrity.'templates/scripts'
    if ($scriptCountRule -and ($scriptCountRule.PSObject.Properties.Name -contains 'exact')) {
        $expected = [int]$scriptCountRule.exact
        if ($scriptNames.Count -ne $expected) {
            Fail "projectBootstrap.scripts expected $expected entries, found $($scriptNames.Count)"
        }
    }

    foreach ($script in $scriptNames) {
        if ($script -match '[\\/]') {
            Fail "script entry must be a file name only: $script"
            continue
        }
        $scriptPath = Join-Path (Join-Path $RepoRoot 'templates/scripts') $script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            Fail "projectBootstrap.scripts references missing file: templates/scripts/$script"
        }
    }

    foreach ($rel in $criticalPaths) {
        $normalized = $rel -replace '\\', '/'
        if (-not ($normalized -eq 'CLAUDE.md' -or $normalized.StartsWith('.claude/') -or $normalized.StartsWith('.local/') -or $normalized -eq '.gitignore')) {
            Fail "critical path is outside bootstrap output surface: $normalized"
        }
    }

    Write-Host "OK:  projectBootstrap.scripts ($($scriptNames.Count) entries)"
    Write-Host "OK:  projectBootstrap.criticalPaths ($($criticalPaths.Count) entries)"
}

if ($failed) {
    throw "Manifest verification failed. Update templates or bootstrap-manifest.json."
}

Write-Host ""
Write-Host "All bootstrap manifest checks passed."
