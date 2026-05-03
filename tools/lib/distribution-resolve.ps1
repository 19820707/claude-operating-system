# distribution-resolve.ps1 — Dot-source only: resolve files for distribution pack/verify
# Requires: $RepoRoot set by caller

function Import-DistributionManifest {
    param([string]$Root)
    $p = Join-Path $Root 'distribution-manifest.json'
    if (-not (Test-Path -LiteralPath $p)) { throw "missing distribution-manifest.json" }
    return (Get-Content -LiteralPath $p -Raw -Encoding utf8 | ConvertFrom-Json)
}

function Get-DistributionRelativePath {
    param([string]$RepoRoot, [string]$FullPath)
    $r = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $f = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $f.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    return $f.Substring($r.Length).TrimStart('\', '/').Replace('\', '/')
}

function Test-DistributionPathExcluded {
    param([string]$NormalizedRelativePath, [string[]]$Regexes)
    foreach ($rx in $Regexes) {
        if ([string]::IsNullOrWhiteSpace($rx)) { continue }
        try {
            if ([regex]::IsMatch($NormalizedRelativePath, $rx, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                return $true
            }
        }
        catch {
            throw "invalid excludePathRegex: $rx — $($_.Exception.Message)"
        }
    }
    return $false
}

function Get-DistributionPackagedRelativePaths {
    param(
        [string]$RepoRoot,
        [object]$Manifest
    )
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rx = @($Manifest.excludePathRegexes | ForEach-Object { [string]$_ })

    foreach ($rf in @($Manifest.rootFiles | ForEach-Object { [string]$_ })) {
        $full = Join-Path $RepoRoot ($rf -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $full) {
            $rel = Get-DistributionRelativePath -RepoRoot $RepoRoot -FullPath $full
            if ($rel -and -not (Test-DistributionPathExcluded -NormalizedRelativePath $rel -Regexes $rx)) {
                [void]$set.Add($rel)
            }
        }
    }

    foreach ($tree in @($Manifest.includeTrees)) {
        $base = [string]$tree.path
        $fullDir = Join-Path $RepoRoot ($base -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $fullDir)) { continue }
        $skips = @()
        if ($tree.PSObject.Properties['skipPathPrefixes']) {
            $skips = @($tree.skipPathPrefixes | ForEach-Object { ([string]$_).Replace('\', '/').TrimEnd('/') + '/' })
        }
        Get-ChildItem -LiteralPath $fullDir -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = Get-DistributionRelativePath -RepoRoot $RepoRoot -FullPath $_.FullName
            if (-not $rel) { return }
            $norm = $rel.Replace('\', '/')
            $skipThis = $false
            foreach ($sx in $skips) {
                if ($norm.StartsWith($sx, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $skipThis = $true
                    break
                }
            }
            if ($skipThis) { return }
            if (-not (Test-DistributionPathExcluded -NormalizedRelativePath $norm -Regexes $rx)) {
                [void]$set.Add($norm)
            }
        }
    }

    return @($set | Sort-Object)
}
