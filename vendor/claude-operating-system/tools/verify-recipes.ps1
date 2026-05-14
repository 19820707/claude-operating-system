# verify-recipes.ps1 — recipe-manifest.json + Markdown section contract
#   pwsh ./tools/verify-recipes.ps1 [-Json] [-Strict]

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

$sectionPatterns = @(
    @{ n = 'Objective'; re = '(?m)^##\s+Objective\b' }
    @{ n = 'When to use'; re = '(?m)^##\s+When to use\b' }
    @{ n = 'Commands'; re = '(?m)^##\s+Commands\b' }
    @{ n = 'Expected result'; re = '(?m)^##\s+Expected result\b' }
    @{ n = 'Acceptable warnings'; re = '(?m)^##\s+Acceptable warnings\b' }
    @{ n = 'Unacceptable warnings/failures'; re = '(?m)^##\s+Unacceptable warnings/failures\b' }
    @{ n = 'Next step if it fails'; re = '(?m)^##\s+Next step if it fails\b' }
)

try {
    $mfPath = Join-Path $RepoRoot 'recipe-manifest.json'
    $schemaPath = Join-Path $RepoRoot 'schemas/recipe-manifest.schema.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing recipe-manifest.json' }
    if (-not (Test-Path -LiteralPath $schemaPath)) { throw 'missing schemas/recipe-manifest.schema.json' }
    $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    $playbookIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pbPath = Join-Path $RepoRoot 'playbook-manifest.json'
    if (Test-Path -LiteralPath $pbPath) {
        $pb = Get-Content -LiteralPath $pbPath -Raw | ConvertFrom-Json
        foreach ($p in @($pb.playbooks)) { [void]$playbookIds.Add([string]$p.id) }
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rc in @($mf.recipes)) {
        $id = [string]$rc.id
        if ($ids.Contains($id)) {
            [void]$failures.Add("duplicate recipe id: $id")
            continue
        }
        [void]$ids.Add($id)

        $rel = [string]$rc.path
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            [void]$failures.Add("recipe path missing: $rel")
            continue
        }
        if ($rel -notmatch '^recipes/[a-z0-9-]+\.md$') {
            [void]$failures.Add("recipe path must be recipes/<slug>.md: $rel")
        }

        if ($rc.PSObject.Properties.Name -contains 'relatedPlaybook') {
            $rpb = [string]$rc.relatedPlaybook
            if (-not [string]::IsNullOrWhiteSpace($rpb) -and -not $playbookIds.Contains($rpb)) {
                [void]$failures.Add("recipe $id relatedPlaybook '$rpb' not found in playbook-manifest.json")
            }
        }

        if ($rc.PSObject.Properties.Name -contains 'relatedDocs') {
            foreach ($d in @($rc.relatedDocs | ForEach-Object { [string]$_ })) {
                if ([string]::IsNullOrWhiteSpace($d)) { continue }
                $df = Join-Path $RepoRoot ($d -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $df)) {
                    [void]$failures.Add("recipe $id relatedDocs missing: $d")
                }
            }
        }

        $body = Get-Content -LiteralPath $full -Raw
        foreach ($sec in $sectionPatterns) {
            if ($body -notmatch $sec.re) {
                $msg = "recipe $id missing section: $($sec.n) ($rel)"
                if ($Strict) {
                    [void]$failures.Add($msg)
                }
                else {
                    [void]$warnings.Add($msg)
                }
            }
        }

        if ($body -notmatch '\]\([^)]*docs/' -and $body -notmatch '\]\([^)]*policies/') {
            [void]$warnings.Add("recipe ${id}: add markdown links to docs/ or policies/ (avoid inlining long policy blocks)")
        }
    }

    $recRoot = Join-Path $RepoRoot 'recipes'
    if (Test-Path -LiteralPath $recRoot) {
        foreach ($f in @(Get-ChildItem -LiteralPath $recRoot -Filter '*.md' -File | Where-Object { $_.Name -ne 'README.md' })) {
            $relPath = ('recipes/' + $f.Name) -replace '\\', '/'
            $listed = $false
            foreach ($rc in @($mf.recipes)) {
                if ([string]$rc.path -eq $relPath) { $listed = $true; break }
            }
            if (-not $listed) {
                [void]$failures.Add("recipes/$($f.Name) exists but is not listed in recipe-manifest.json")
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'recipes'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'recipe-manifest + Markdown contract' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-recipes' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-recipes: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
