# intelligence-fabric.ps1 — Cross-project intelligence: contribute, inherit, risk-brief, sync-all
# Maintains heuristics/cross-project-evidence.json as shared pattern repository.
#   pwsh ./tools/intelligence-fabric.ps1 -Mode contribute -ProjectPath ../other-project
#   pwsh ./tools/intelligence-fabric.ps1 -Mode inherit -ProjectPath ../other-project
#   pwsh ./tools/intelligence-fabric.ps1 -Mode risk-brief -ProjectPath ../new-project
#   pwsh ./tools/intelligence-fabric.ps1 -Mode sync-all -ProjectPath ../

param(
    [ValidateSet('contribute', 'inherit', 'risk-brief', 'sync-all')]
    [string]$Mode = 'contribute',
    [string]$ProjectPath = '.',
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$evidencePath = Join-Path $RepoRoot 'heuristics/cross-project-evidence.json'
$findings     = [ordered]@{ mode = $Mode }

function Load-Evidence {
    if (Test-Path -LiteralPath $evidencePath) {
        try {
            $doc = (Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8) | ConvertFrom-Json
            # Ensure patterns key exists
            if (-not ($doc.PSObject.Properties.Name -contains 'patterns')) {
                $doc | Add-Member -NotePropertyName 'patterns' -NotePropertyValue ([ordered]@{}) -Force
            }
            return $doc
        } catch { }
    }
    return [ordered]@{ version = 2; patterns = [ordered]@{}; sources = @(); lastUpdated = '' }
}

function Save-Evidence {
    param($Doc)
    $hDir = Join-Path $RepoRoot 'heuristics'
    if (-not (Test-Path -LiteralPath $hDir)) { New-Item -ItemType Directory -Path $hDir -Force | Out-Null }
    $Doc.lastUpdated = (Get-Date).ToUniversalTime().ToString('o')
    $Doc | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding utf8
}

# ── Mode: contribute ──────────────────────────────────────────────────────────
if ($Mode -eq 'contribute') {
    $projRoot = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $projName = [System.IO.Path]::GetFileName($projRoot)
    $evidence = Load-Evidence
    $patterns = $evidence.patterns

    $contributed = 0

    # From learned-baselines.json
    $baselinePath = Join-Path $projRoot '.claude/learned-baselines.json'
    if (Test-Path -LiteralPath $baselinePath) {
        try {
            $bl = (Get-Content -LiteralPath $baselinePath -Raw -Encoding utf8) | ConvertFrom-Json
            foreach ($prop in $bl.file_risk_overrides.PSObject.Properties) {
                $key = "file-risk-$($prop.Name -replace '[/\\]','-' -replace '\.ps1$','')"
                $p   = [double]$prop.Value
                if ($p -lt 0.3) { continue }  # only contribute notable risks
                if (-not ($patterns.PSObject.Properties.Name -contains $key)) {
                    $patterns | Add-Member -NotePropertyName $key -NotePropertyValue ([ordered]@{
                        confirmed_in   = @($projName)
                        total          = 1
                        p_recurrence   = $p
                        risk_if_ignored = if ($p -ge 0.6) { 'HIGH' } elseif ($p -ge 0.4) { 'MEDIUM' } else { 'LOW' }
                        source_file    = [string]$prop.Name
                        last_seen      = (Get-Date).ToUniversalTime().ToString('o')
                    }) -Force
                } else {
                    $existing = $patterns.PSObject.Properties[$key].Value
                    if ($existing.confirmed_in -notcontains $projName) {
                        $existing.confirmed_in += $projName
                        $existing.total = $existing.confirmed_in.Count
                        $existing.p_recurrence = [Math]::Round(($existing.p_recurrence + $p) / 2, 4)
                        $existing.last_seen = (Get-Date).ToUniversalTime().ToString('o')
                    }
                }
                $contributed++
            }
        } catch { }
    }

    # From heuristics operational.md (export high-confidence patterns)
    $heurPath = Join-Path $projRoot '.claude/heuristics/operational.md'
    if (Test-Path -LiteralPath $heurPath) {
        try {
            $src = Get-Content -LiteralPath $heurPath -Raw -Encoding utf8
            $hMatches = [regex]::Matches($src, '(?m)^###\s+(H[\w-]+)\s+[—–-]+\s+(.+)$')
            foreach ($hm in $hMatches) {
                $id    = $hm.Groups[1].Value
                $title = $hm.Groups[2].Value.Trim()
                $key   = "heuristic-$($id.ToLower())"
                if (-not ($patterns.PSObject.Properties.Name -contains $key)) {
                    $patterns | Add-Member -NotePropertyName $key -NotePropertyValue ([ordered]@{
                        confirmed_in   = @($projName)
                        total          = 1
                        p_recurrence   = 0.7
                        risk_if_ignored = 'MEDIUM'
                        heuristic_ref  = $id
                        title          = $title
                        last_seen      = (Get-Date).ToUniversalTime().ToString('o')
                    }) -Force
                } else {
                    $existing = $patterns.PSObject.Properties[$key].Value
                    if ($existing.confirmed_in -notcontains $projName) {
                        $existing.confirmed_in += $projName
                        $existing.total = $existing.confirmed_in.Count
                        $existing.last_seen = (Get-Date).ToUniversalTime().ToString('o')
                    }
                }
                $contributed++
            }
        } catch { }
    }

    $evidence.patterns = $patterns
    if (-not $DryRun) { Save-Evidence -Doc $evidence }

    [void]$checks.Add([ordered]@{ name = 'contribute'; status = 'ok'; detail = "contributed $contributed pattern(s) from $projName" })
    $findings.contributed = $contributed
    $findings.projectName = $projName

    if (-not $Json) {
        Write-Host "intelligence-fabric [contribute]"
        Write-Host "Project    : $projRoot"
        Write-Host "Contributed: $contributed pattern(s)"
    }
}

# ── Mode: inherit ─────────────────────────────────────────────────────────────
elseif ($Mode -eq 'inherit') {
    $projRoot = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $projName = [System.IO.Path]::GetFileName($projRoot)
    $statePath = Join-Path $projRoot '.claude/session-state.md'
    $evidence  = Load-Evidence
    $patterns  = $evidence.patterns

    $inherited = [System.Collections.Generic.List[object]]::new()
    foreach ($prop in $patterns.PSObject.Properties) {
        $p = $prop.Value
        if ([int]$p.total -lt 2) { continue }  # only cross-project confirmed patterns
        if ($p.confirmed_in -contains $projName) { continue }  # skip own contributions

        [void]$inherited.Add([ordered]@{
            key         = $prop.Name
            total       = $p.total
            risk        = [string]$p.risk_if_ignored
            title       = if ($p.PSObject.Properties.Name -contains 'title') { [string]$p.title } else { $prop.Name }
            heuristicRef = if ($p.PSObject.Properties.Name -contains 'heuristic_ref') { [string]$p.heuristic_ref } else { '' }
        })
    }

    if ($inherited.Count -gt 0 -and (Test-Path -LiteralPath $statePath)) {
        $injectBlock = "`n## Inherited Intelligence — $(Get-Date -Format 'yyyy-MM-dd')`n`n"
        $injectBlock += "> $($inherited.Count) pattern(s) inherited from cross-project intelligence (confirmed in 2+ projects)`n`n"
        foreach ($i in $inherited) {
            $ref = if ($i.heuristicRef) { " [→ $($i.heuristicRef)]" } else { '' }
            $injectBlock += "- **[$($i.risk)]** $($i.title)$ref _(seen in $($i.total) projects)_`n"
        }
        $existing = Get-Content -LiteralPath $statePath -Raw -Encoding utf8
        if (-not ($existing -match 'Inherited Intelligence')) {
            $newContent = $existing.TrimEnd() + "`n" + $injectBlock
            [System.IO.File]::WriteAllText($statePath, $newContent, [System.Text.Encoding]::UTF8)
        }
    }

    [void]$checks.Add([ordered]@{ name = 'inherit'; status = 'ok'; detail = "inherited $($inherited.Count) pattern(s) into $projName" })
    $findings.inherited = $inherited.Count

    if (-not $Json) {
        Write-Host "intelligence-fabric [inherit]"
        Write-Host "Inherited $($inherited.Count) pattern(s) from cross-project intelligence"
        foreach ($i in $inherited) { Write-Host "  [$($i.risk)] $($i.title)" }
    }
}

# ── Mode: risk-brief ──────────────────────────────────────────────────────────
elseif ($Mode -eq 'risk-brief') {
    $projRoot  = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $projName  = [System.IO.Path]::GetFileName($projRoot)
    $briefPath = Join-Path $projRoot '.claude/inherited-risk-brief.md'

    # Detect stack from project files
    $stackSignals = [System.Collections.Generic.List[string]]::new()
    $checks2 = @(
        @{ file = 'package.json';    tag = 'node' }
        @{ file = 'Dockerfile';      tag = 'docker' }
        @{ file = 'requirements.txt'; tag = 'python' }
        @{ file = 'go.mod';          tag = 'go' }
        @{ file = 'Cargo.toml';      tag = 'rust' }
        @{ file = 'tsconfig.json';   tag = 'typescript' }
        @{ file = 'vite.config.ts';  tag = 'vite' }
        @{ file = 'next.config.js';  tag = 'nextjs' }
        @{ file = '.env.example';    tag = 'env' }
    )
    foreach ($c in $checks2) {
        $fp = Join-Path $projRoot $c.file
        if (Test-Path -LiteralPath $fp) { [void]$stackSignals.Add($c.tag) }
    }

    # Match patterns from evidence
    $evidence = Load-Evidence
    $matched  = [System.Collections.Generic.List[object]]::new()
    foreach ($prop in $evidence.patterns.PSObject.Properties) {
        $p     = $prop.Value
        $ptags = @($prop.Name -split '-')
        $match = @($stackSignals | Where-Object { $ptags -contains $_ }).Count -gt 0
        if ($match -or [int]$p.total -ge 3) {
            [void]$matched.Add([ordered]@{ key = $prop.Name; risk = [string]$p.risk_if_ignored; total = [int]$p.total; title = if ($p.PSObject.Properties.Name -contains 'title') { [string]$p.title } else { $prop.Name } })
        }
    }

    $brief = @"
# Inherited Risk Brief — $projName

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC

## Stack Detected
$($stackSignals -join ', ')

## Known Risks for This Stack ($($matched.Count) patterns)

"@
    foreach ($m in ($matched | Sort-Object { $_.risk } | Select-Object -First 10)) {
        $brief += "- **[$($m.risk)]** $($m.title) _(seen in $($m.total) project(s))_`n"
    }
    $brief += "`n## Source`nGenerated from cross-project intelligence fabric. Update via: ``pwsh tools/intelligence-fabric.ps1 -Mode sync-all``"

    [System.IO.File]::WriteAllText($briefPath, $brief, [System.Text.Encoding]::UTF8)

    [void]$checks.Add([ordered]@{ name = 'risk-brief'; status = 'ok'; detail = "brief written with $($matched.Count) pattern(s)" })
    $findings.briefPath = $briefPath
    $findings.stack     = @($stackSignals)
    $findings.patterns  = $matched.Count

    if (-not $Json) {
        Write-Host "intelligence-fabric [risk-brief]"
        Write-Host "Stack   : $($stackSignals -join ', ')"
        Write-Host "Patterns: $($matched.Count) matched"
        Write-Host "Written : $briefPath"
    }
}

# ── Mode: sync-all ────────────────────────────────────────────────────────────
elseif ($Mode -eq 'sync-all') {
    $scanRoot = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $projects = @(Get-ChildItem -LiteralPath $scanRoot -Directory -Recurse -Depth 2 |
        Where-Object { Test-Path (Join-Path $_.FullName '.claude') })

    $synced = 0
    foreach ($proj in $projects) {
        if ($proj.FullName -eq $RepoRoot) { continue }  # skip self
        try {
            & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/intelligence-fabric.ps1') `
                -Mode contribute -ProjectPath $proj.FullName 2>$null
            $synced++
        } catch { }
    }

    [void]$checks.Add([ordered]@{ name = 'sync-all'; status = 'ok'; detail = "synced $synced of $($projects.Count) project(s)" })
    $findings.synced   = $synced
    $findings.scanned  = $projects.Count

    if (-not $Json) {
        Write-Host "intelligence-fabric [sync-all]"
        Write-Host "Scanned: $($projects.Count) project(s) with .claude/"
        Write-Host "Synced : $synced"
    }
}

$sw.Stop()
$st = if ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'intelligence-fabric' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @() `
    -Findings @(@($findings))

if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
exit 0
