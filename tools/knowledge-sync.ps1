# knowledge-sync.ps1 — Cross-project heuristic pattern exchange
# Exports confirmed patterns from a project's heuristics and learning-log.
# Imports patterns confirmed across multiple projects into a target project.
#   pwsh ./tools/knowledge-sync.ps1 -Mode export -ProjectPath ../other-project
#   pwsh ./tools/knowledge-sync.ps1 -Mode import -ProjectPath ../other-project
#   pwsh ./tools/knowledge-sync.ps1 -Mode report [-Json]
#   pwsh ./tools/knowledge-sync.ps1 -Mode export -ProjectPath ../x -DryRun

param(
    [ValidateSet('export', 'import', 'report')]
    [string]$Mode = 'report',
    [string]$ProjectPath = '',
    [int]$MinConfidence = 2,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$evidencePath = Join-Path $RepoRoot 'heuristics/cross-project-evidence.json'
$findings     = [ordered]@{ mode = $Mode; dryRun = [bool]$DryRun }

function Read-Evidence {
    if (Test-Path -LiteralPath $evidencePath) {
        try { return (Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8) | ConvertFrom-Json }
        catch { }
    }
    return [ordered]@{ version = 1; sources = @() }
}

function Extract-PatternsFromProject {
    param([string]$ProjRoot)
    $patterns = [System.Collections.Generic.List[object]]::new()

    $hDir = Join-Path $ProjRoot '.claude/heuristics'
    if (Test-Path -LiteralPath $hDir) {
        foreach ($hf in (Get-ChildItem -LiteralPath $hDir -Filter '*.md' -File)) {
            try {
                $src = Get-Content -LiteralPath $hf.FullName -Raw -Encoding utf8
                foreach ($m in ([regex]::Matches($src, '(?m)^###\s+(H[\w-]+)\s+[—–-]+\s+(.+)$'))) {
                    $id    = $m.Groups[1].Value
                    $title = $m.Groups[2].Value.Trim()
                    $after = $src.Substring($m.Index + $m.Length)
                    $rm    = [regex]::Match($after, '(?m)^\*\*Rule:\*\*\s*(.+)$')
                    $rule  = if ($rm.Success) { $rm.Groups[1].Value.Trim() } else { $title }
                    [void]$patterns.Add([ordered]@{ id = $id; title = $title; rule = $rule; source = 'heuristics'; confirmed = 1 })
                }
            } catch { }
        }
    }

    $logPath = Join-Path $ProjRoot '.claude/learning-log.md'
    if (Test-Path -LiteralPath $logPath) {
        try {
            $src = Get-Content -LiteralPath $logPath -Raw -Encoding utf8
            foreach ($m in ([regex]::Matches($src, '(?m)^\s*-\s+H\??\s+[—–-]+\s+(.+)$'))) {
                $rule = $m.Groups[1].Value.Trim()
                [void]$patterns.Add([ordered]@{ id = 'H?'; title = $rule; rule = $rule; source = 'learning-log'; confirmed = 1 })
            }
        } catch { }
    }
    return @($patterns)
}

function Get-AggregatedPatterns {
    param($Evidence)
    $agg = [System.Collections.Generic.Dictionary[string, object]]::new()
    foreach ($src in @($Evidence.sources)) {
        if (-not $src) { continue }
        foreach ($pat in @($src.patterns)) {
        if (-not $pat) { continue }
            $key = [string]$pat.rule
            if ($agg.ContainsKey($key)) {
                $agg[$key].confirmed = [int]$agg[$key].confirmed + 1
                [void]$agg[$key].sources.Add([string]$src.projectName)
            } else {
                $obj = [ordered]@{
                    id        = [string]$pat.id
                    title     = [string]$pat.title
                    rule      = [string]$pat.rule
                    confirmed = 1
                    sources   = [System.Collections.Generic.List[string]]::new()
                }
                [void]$obj.sources.Add([string]$src.projectName)
                $agg[$key] = $obj
            }
        }
    }
    return @($agg.Values | Sort-Object { -[int]$_.confirmed })
}

# ── Mode: export ──────────────────────────────────────────────────────────────
if ($Mode -eq 'export') {
    if (-not $ProjectPath) { throw '-ProjectPath is required for export mode' }
    $projRoot = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $projName = [System.IO.Path]::GetFileName($projRoot)

    $patterns = Extract-PatternsFromProject -ProjRoot $projRoot

    $evidence = Read-Evidence
    $sourcesList = [System.Collections.Generic.List[object]]::new()
    foreach ($s in @($evidence.sources)) {
        if ([string]$s.project -ne $projRoot -and [string]$s.projectName -ne $projName) {
            [void]$sourcesList.Add($s)
        }
    }
    [void]$sourcesList.Add([ordered]@{
        projectName  = $projName
        project      = $projRoot
        exported     = (Get-Date).ToUniversalTime().ToString('o')
        patternCount = $patterns.Count
        patterns     = $patterns
    })

    $updated = [ordered]@{
        version     = 1
        lastUpdated = (Get-Date).ToUniversalTime().ToString('o')
        sources     = @($sourcesList)
    }

    if (-not $DryRun) {
        $hDir = Join-Path $RepoRoot 'heuristics'
        if (-not (Test-Path -LiteralPath $hDir)) { New-Item -ItemType Directory -Path $hDir -Force | Out-Null }
        $updated | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    }

    [void]$checks.Add([ordered]@{ name = 'export'; status = 'ok'; detail = "exported $($patterns.Count) patterns from $projName$(if ($DryRun) { ' (dry-run)' })" })
    $findings.exported = $patterns.Count
    $findings.projectName = $projName

    if (-not $Json) {
        Write-Host "knowledge-sync [export$(if ($DryRun) { ' dry-run' })]"
        Write-Host "Project : $projRoot"
        Write-Host "Patterns: $($patterns.Count) extracted"
        Write-Host "Written : $(if ($DryRun) { 'skipped (dry-run)' } else { $evidencePath })"
    }
}

# ── Mode: import ──────────────────────────────────────────────────────────────
elseif ($Mode -eq 'import') {
    if (-not $ProjectPath) { throw '-ProjectPath is required for import mode' }
    $projRoot = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
    $logPath  = Join-Path $projRoot '.claude/learning-log.md'

    if (-not (Test-Path -LiteralPath $evidencePath)) {
        [void]$warnings.Add('cross-project-evidence.json not found — run export first')
        [void]$checks.Add([ordered]@{ name = 'import'; status = 'warn'; detail = 'no evidence file' })
    } else {
        $evidence    = Read-Evidence
        $toImport    = @(Get-AggregatedPatterns -Evidence $evidence | Where-Object { [int]$_.confirmed -ge $MinConfidence })

        if ($toImport.Count -gt 0 -and -not $DryRun) {
            $block  = "`n## Inherited Knowledge — $(Get-Date -Format 'yyyy-MM-dd')`n"
            $block += "> Patterns confirmed in $([array]$evidence.sources.Count) project(s) with min confidence $MinConfidence`n`n"
            foreach ($p in $toImport) {
                $block += "- **[$($p.id)]** $($p.rule)  _(confirmed=$($p.confirmed), sources: $($p.sources -join ', '))_`n"
            }
            $existing   = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -Encoding utf8 } else { '' }
            $newContent = $existing.TrimEnd() + "`n" + $block
            [System.IO.File]::WriteAllText($logPath, $newContent, [System.Text.Encoding]::UTF8)
        }

        [void]$checks.Add([ordered]@{ name = 'import'; status = 'ok'; detail = "injected=$($toImport.Count) dryRun=$DryRun" })
        $findings.injected = $toImport.Count

        if (-not $Json) {
            Write-Host "knowledge-sync [import$(if ($DryRun) { ' dry-run' })]"
            Write-Host "Target  : $projRoot"
            Write-Host "Injected: $($toImport.Count) patterns (minConfidence=$MinConfidence)$(if ($DryRun) { ' (dry-run)' })"
        }
    }
}

# ── Mode: report ──────────────────────────────────────────────────────────────
elseif ($Mode -eq 'report') {
    if (-not (Test-Path -LiteralPath $evidencePath)) {
        [void]$warnings.Add('cross-project-evidence.json not found — run export first')
        [void]$checks.Add([ordered]@{ name = 'report'; status = 'warn'; detail = 'no evidence file' })
    } else {
        $evidence = Read-Evidence
        $sorted   = Get-AggregatedPatterns -Evidence $evidence
        [void]$checks.Add([ordered]@{ name = 'report'; status = 'ok'; detail = "$([array]$evidence.sources.Count) source(s), $($sorted.Count) unique patterns" })
        $findings.sources  = [array]$evidence.sources.Count
        $findings.patterns = @($sorted)

        if (-not $Json) {
            Write-Host "knowledge-sync [report]"
            Write-Host "Sources : $([array]$evidence.sources.Count)"
            Write-Host "Patterns: $($sorted.Count)"
            Write-Host ''
            foreach ($p in $sorted) {
                $mark = if ([int]$p.confirmed -ge $MinConfidence) { 'CONFIRMED' } else { '        ' }
                Write-Host "  $mark [$($p.id)] ($($p.confirmed)x) $($p.rule)"
                Write-Host "            Sources: $($p.sources -join ', ')"
            }
        }
    }
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'knowledge-sync' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@($findings))

if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }

if ($failures.Count -gt 0) { exit 1 }
exit 0
