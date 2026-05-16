# sync-manifests.ps1 — Auto-sync script-manifest, component-manifest,
#   compatibility-manifest, and bootstrap-manifest from disk state.
# Adds missing entries for new tools/*.ps1 and templates/scripts/*.sh.
# Preserves all existing metadata. Never auto-deletes (warns instead).
# Run automatically via pre-commit hook; also usable standalone.
#   pwsh ./tools/sync-manifests.ps1            # sync in-place
#   pwsh ./tools/sync-manifests.ps1 -WhatIf   # preview — no writes
#   pwsh ./tools/sync-manifests.ps1 -Json      # machine-readable envelope

param(
    [switch]$WhatIf,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw       = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()
$added    = [System.Collections.Generic.List[string]]::new()
$stale    = [System.Collections.Generic.List[string]]::new()

# ── Inference helpers ──────────────────────────────────────────────────────────

function Get-InferredId {
    param([string]$RelPath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($RelPath)
    if ($RelPath -match '(?i)^tools/lib/') { return "lib-$($name.ToLower())" }
    return $name.ToLower()
}

function Get-InferredDescription {
    param([string]$FullPath)
    try {
        $lines = Get-Content -LiteralPath $FullPath -TotalCount 8 -Encoding utf8
        $hit = $lines | Where-Object { $_ -match '^#\s+\S' -and $_ -notmatch '^#!/' } | Select-Object -First 1
        if ($hit) { return ($hit -replace '^#\s+', '' -replace '\s+[—–-]\s.*$', '').Trim() }
    } catch { }
    return ''
}

function Get-InferredKind {
    param([string]$Id)
    if ($Id -match '^verify-')                                             { return 'validator' }
    if ($Id -match '^lib-')                                                { return 'lib' }
    if ($Id -match '^os-validate')                                         { return 'orchestrator' }
    if ($Id -match '^os-')                                                 { return 'orchestrator' }
    if ($Id -match '^sync-|sync$')                                         { return 'sync' }
    if ($Id -match '^(learn|outcome|knowledge|intelligence|decision-audit|risk-calibrat)') { return 'analyzer' }
    if ($Id -match '(intervention|predictive)')                            { return 'validator' }
    return 'tool'
}

function Get-InferredMaturity {
    param([string]$FullPath)
    try {
        $head = (Get-Content -LiteralPath $FullPath -TotalCount 10 -Encoding utf8) -join "`n"
        if ($head -match '(?i)maturity:\s*stable') { return 'stable' }
    } catch { }
    return 'experimental'
}

function Get-InferredExitPolicy {
    param([string]$FullPath)
    try {
        $raw = Get-Content -LiteralPath $FullPath -Raw -Encoding utf8
        if ($raw -match '\bexit 1\b') { return 'exit1-on-fail' }
    } catch { }
    return 'exit0-always'
}

function New-ScriptEntry {
    param([string]$RelPath)
    $full     = Join-Path $RepoRoot $RelPath
    $id       = Get-InferredId -RelPath $RelPath
    $maturity = Get-InferredMaturity -FullPath $full
    return [ordered]@{
        path           = $RelPath
        id             = $id
        description    = Get-InferredDescription -FullPath $full
        kind           = Get-InferredKind -Id $id
        maturity       = $maturity
        defaultEnabled = $true
        requires       = @('pwsh')
        writes         = @()
        exitPolicy     = Get-InferredExitPolicy -FullPath $full
        safeToRunInCI  = ($maturity -eq 'stable')
    }
}

function New-ShellEntry {
    param([string]$RelPath)
    $id = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($RelPath))
    return [ordered]@{ path = $RelPath; id = $id.ToLower(); maturity = 'stable'; defaultEnabled = $true }
}

# ── Load manifests ─────────────────────────────────────────────────────────────

$smPath = Join-Path $RepoRoot 'script-manifest.json'
$cmPath = Join-Path $RepoRoot 'component-manifest.json'
$cxPath = Join-Path $RepoRoot 'compatibility-manifest.json'
$bmPath = Join-Path $RepoRoot 'bootstrap-manifest.json'

$sm = Get-Content -LiteralPath $smPath -Raw | ConvertFrom-Json
$cm = Get-Content -LiteralPath $cmPath -Raw | ConvertFrom-Json
$cx = Get-Content -LiteralPath $cxPath -Raw | ConvertFrom-Json
$bm = Get-Content -LiteralPath $bmPath -Raw | ConvertFrom-Json

# ── Scan disk ──────────────────────────────────────────────────────────────────

$diskPs1 = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tools') -Recurse -Filter *.ps1 -File |
    ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/' } | Sort-Object)

$diskSh = @()
$shDir = Join-Path $RepoRoot 'templates/scripts'
if (Test-Path -LiteralPath $shDir) {
    $diskSh = @(Get-ChildItem -LiteralPath $shDir -Filter *.sh -File |
        ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/' } | Sort-Object)
}

# ── 1. script-manifest.json ───────────────────────────────────────────────────

$listedPs1 = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($t in @($sm.tools)) { [void]$listedPs1.Add(([string]$t.path).Replace('\', '/')) }

$listedSh = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($sm.PSObject.Properties.Name -contains 'shellScripts') {
    foreach ($t in @($sm.shellScripts)) { [void]$listedSh.Add(([string]$t.path).Replace('\', '/')) }
}

$newPs1 = [System.Collections.Generic.List[object]]::new()
foreach ($p in $diskPs1) {
    if (-not $listedPs1.Contains($p)) {
        [void]$newPs1.Add([pscustomobject](New-ScriptEntry -RelPath $p))
        [void]$added.Add("script-manifest +tool $p")
    }
}

$newSh = [System.Collections.Generic.List[object]]::new()
foreach ($s in $diskSh) {
    if (-not $listedSh.Contains($s)) {
        [void]$newSh.Add([pscustomobject](New-ShellEntry -RelPath $s))
        [void]$added.Add("script-manifest +shell $s")
    }
}

foreach ($t in @($sm.tools)) {
    $full = Join-Path $RepoRoot ([string]$t.path)
    if (-not (Test-Path -LiteralPath $full)) { [void]$stale.Add("script-manifest stale: $([string]$t.path)") }
}

if (($newPs1.Count -gt 0 -or $newSh.Count -gt 0) -and -not $WhatIf) {
    foreach ($t in $newPs1) { $sm.tools += $t }
    if (-not ($sm.PSObject.Properties.Name -contains 'shellScripts')) {
        $sm | Add-Member -NotePropertyName 'shellScripts' -NotePropertyValue @() -Force
    }
    foreach ($s in $newSh) { $sm.shellScripts += $s }
    $sm | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $smPath -Encoding utf8
}
[void]$checks.Add([ordered]@{ name = 'script-manifest'; status = 'ok'; detail = "+$($newPs1.Count) ps1  +$($newSh.Count) sh  stale=$($stale.Count)" })

# ── 2. component-manifest.json ────────────────────────────────────────────────

$allToolIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($t in @($sm.tools)) { [void]$allToolIds.Add([string]$t.id) }
foreach ($t in $newPs1)       { [void]$allToolIds.Add([string]$t.id) }

$coveredIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($comp in @($cm.components)) {
    foreach ($m in @($comp.members)) {
        $k = [string]$m.kind
        if ($k -eq 'tool' -or $k -eq 'shell') { [void]$coveredIds.Add([string]$m.id) }
    }
}

$stableDelivery = @($cm.components | Where-Object { $_.id -eq 'stable-delivery' }) | Select-Object -First 1
$cmNewMembers = [System.Collections.Generic.List[object]]::new()

foreach ($tid in $allToolIds) {
    if (-not $coveredIds.Contains($tid)) {
        [void]$cmNewMembers.Add([pscustomobject]@{ kind = 'tool'; id = $tid })
        [void]$added.Add("component-manifest +tool $tid")
    }
}

if ($cmNewMembers.Count -gt 0 -and -not $WhatIf -and $stableDelivery) {
    foreach ($m in $cmNewMembers) { $stableDelivery.members += $m }
    $cm | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cmPath -Encoding utf8
}
[void]$checks.Add([ordered]@{ name = 'component-manifest'; status = 'ok'; detail = "+$($cmNewMembers.Count) member(s)" })

# ── 3. compatibility-manifest.json ────────────────────────────────────────────

$cxValidatorIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($v in @($cx.validators)) { [void]$cxValidatorIds.Add([string]$v.id) }

$cxNewValidators = [System.Collections.Generic.List[object]]::new()
foreach ($tid in $allToolIds) {
    if ($tid -match '^verify-' -and -not $cxValidatorIds.Contains($tid)) {
        [void]$cxNewValidators.Add([pscustomobject]@{ id = $tid })
        [void]$added.Add("compatibility-manifest +validator $tid")
    }
}

if ($cxNewValidators.Count -gt 0 -and -not $WhatIf) {
    foreach ($v in $cxNewValidators) { $cx.validators += $v }
    $cx | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cxPath -Encoding utf8
}
[void]$checks.Add([ordered]@{ name = 'compatibility-manifest'; status = 'ok'; detail = "+$($cxNewValidators.Count) validator(s)" })

# ── 4. bootstrap-manifest.json shell count ────────────────────────────────────

$actualShCount = $diskSh.Count
$bmProp = $bm.repoIntegrity.PSObject.Properties['templates/scripts']
$bmUpdated = $false

if ($bmProp) {
    $prevCount = [int]$bmProp.Value.exact
    if ($prevCount -ne $actualShCount) {
        [void]$added.Add("bootstrap-manifest templates/scripts exact $prevCount → $actualShCount")
        $bmUpdated = $true
        if (-not $WhatIf) {
            $bmProp.Value.exact = $actualShCount
            $bm | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bmPath -Encoding utf8
        }
    }
}
[void]$checks.Add([ordered]@{ name = 'bootstrap-manifest'; status = 'ok'; detail = "shell-count=$actualShCount$(if ($bmUpdated) { ' (updated)' })" })

# ── Summary ───────────────────────────────────────────────────────────────────

$sw.Stop()

foreach ($s in $stale) { [void]$warnings.Add($s) }

if (-not $Json) {
    $tag = if ($WhatIf) { ' [what-if]' } else { '' }
    Write-Host "sync-manifests$tag"
    if ($added.Count -gt 0) {
        Write-Host ''
        Write-Host "$(if ($WhatIf) { 'Would apply' } else { 'Applied' }) $($added.Count) change(s):"
        foreach ($a in $added) { Write-Host "  + $a" }
    } else {
        Write-Host '  all manifests in sync'
    }
    if ($stale.Count -gt 0) {
        Write-Host ''
        Write-Host 'Stale entries (file not on disk — remove manually):'
        foreach ($s in $stale) { Write-Host "  ! $s" }
    }
    Write-Host ''
}

$st = if ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'sync-manifests' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @() `
    -Findings @(@([ordered]@{
        whatIf  = [bool]$WhatIf
        added   = $added.Count
        stale   = $stale.Count
        changes = @($added)
    }))

if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
exit 0
