# generate-script-graph.ps1 — Dependency graph for tools/*.ps1
# Extracts call edges by parsing invocation patterns, then writes an adjacency-list
# graph to .claude/script-graph.json. Outputs graph stats to stdout (or -Json envelope).
#   pwsh ./tools/generate-script-graph.ps1
#   pwsh ./tools/generate-script-graph.ps1 -Json
#   pwsh ./tools/generate-script-graph.ps1 -Out .claude/script-graph.json

param(
    [switch]$Json,
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$toolDir = Join-Path $RepoRoot 'tools'
$toolScripts = @(Get-ChildItem -LiteralPath $toolDir -Filter '*.ps1' -File)
$scriptNames = @($toolScripts | ForEach-Object { $_.Name })

# Call patterns that indicate a script invokes another tools/*.ps1
# Each pattern captures the called script name in group 1.
$patterns = @(
    # & (Join-Path $RepoRoot 'tools/foo.ps1') or Join-Path ... 'tools/foo.ps1'
    [regex]"Join-Path[^'`"]*['\`"]tools[/\\]([\w][\w.-]+\.ps1)['\`"]",
    # pwsh -NoProfile -File (path ending in) tools/foo.ps1
    [regex]"pwsh[^'`"]*['\`"]tools[/\\]([\w][\w.-]+\.ps1)['\`"]",
    # Invoke-PwshTool -RelativeTool 'tools/foo.ps1'
    [regex]"Invoke-PwshTool[^'`"]*['\`"]tools[/\\]([\w][\w.-]+\.ps1)['\`"]",
    # Get-OsToolJsonStatus -RelativeTool 'tools/foo.ps1'
    [regex]"RelativeTool\s+['\`"]tools[/\\]([\w][\w.-]+\.ps1)['\`"]",
    # & $env:GITHUB_WORKSPACE/tools/foo.ps1
    [regex]"\`$env:GITHUB_WORKSPACE/tools/([\w][\w.-]+\.ps1)"
)

# Build adjacency list: node -> list of called nodes
$adj = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.HashSet[string]]]::new()
foreach ($s in $scriptNames) { [void]$adj.TryAdd($s, [System.Collections.Generic.HashSet[string]]::new()) }

foreach ($file in $toolScripts) {
    try {
        $src = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    } catch {
        [void]$warnings.Add("Could not read $($file.Name)")
        continue
    }

    foreach ($pat in $patterns) {
        foreach ($m in $pat.Matches($src)) {
            $called = $m.Groups[1].Value
            if ($called -ne $file.Name -and $scriptNames -contains $called) {
                [void]$adj[$file.Name].Add($called)
            }
        }
    }
}

# Compute in-degree for each node
$inDegree = @{}
foreach ($s in $scriptNames) { $inDegree[$s] = 0 }
foreach ($src in $scriptNames) {
    foreach ($tgt in $adj[$src]) {
        $inDegree[$tgt]++
    }
}

# Entry points: no incoming edges (not called by other tools)
$entryPoints = @($scriptNames | Where-Object { $inDegree[$_] -eq 0 })
# Orphans: no incoming AND no outgoing edges
$orphans = @($scriptNames | Where-Object { $inDegree[$_] -eq 0 -and $adj[$_].Count -eq 0 })

# Detect cycles via DFS
$cycleSet = [System.Collections.Generic.HashSet[string]]::new()
function Find-Cycles {
    param([string]$Node, [string[]]$Path)
    if ($Path -contains $Node) {
        $cycleStart = [array]::IndexOf($Path, $Node)
        $cycle = ($Path[$cycleStart..($Path.Length-1)] + $Node) -join ' -> '
        [void]$cycleSet.Add($cycle)
        return
    }
    foreach ($child in $adj[$Node]) {
        Find-Cycles -Node $child -Path ($Path + $Node)
    }
}
foreach ($s in $scriptNames) { Find-Cycles -Node $s -Path @() }

# Build node objects sorted by in-degree desc
$nodes = @($scriptNames | Sort-Object { $inDegree[$_] } -Descending | ForEach-Object {
    [ordered]@{
        id        = $_
        inDegree  = [int]$inDegree[$_]
        outDegree = [int]$adj[$_].Count
    }
})

# Build edge list
$edges = [System.Collections.Generic.List[object]]::new()
foreach ($src in ($scriptNames | Sort-Object)) {
    foreach ($tgt in ($adj[$src] | Sort-Object)) {
        [void]$edges.Add([ordered]@{ from = $src; to = $tgt })
    }
}

$graph = [ordered]@{
    schemaVersion = 1
    generated     = (Get-Date).ToUniversalTime().ToString('o')
    nodeCount     = $nodes.Count
    edgeCount     = $edges.Count
    entryPoints   = $entryPoints
    orphans       = $orphans
    cycles        = @($cycleSet)
    nodes         = $nodes
    edges         = @($edges)
}

# Write output file
$outPath = if ($Out) { $Out } else { Join-Path $RepoRoot '.claude/script-graph.json' }
if (-not $Json) {
    try {
        $graph | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding utf8
        [void]$checks.Add([ordered]@{ name = 'write-graph'; status = 'ok'; detail = $outPath })
    } catch {
        [void]$failures.Add("Could not write graph to $outPath: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'write-graph'; status = 'fail'; detail = $_.Exception.Message })
    }
}

$sw.Stop()

$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'generate-script-graph' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        nodeCount   = $nodes.Count
        edgeCount   = $edges.Count
        entryPoints = $entryPoints
        orphanCount = $orphans.Count
        cycleCount  = $cycleSet.Count
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'generate-script-graph'
    Write-Host "Repo : $RepoRoot"
    Write-Host "Out  : $outPath"
    Write-Host ''
    Write-Host "Nodes : $($nodes.Count)"
    Write-Host "Edges : $($edges.Count)"
    Write-Host "Entry points ($($entryPoints.Count)): $($entryPoints -join ', ')"
    if ($orphans.Count -gt 0) { Write-Host "Orphans ($($orphans.Count)): $($orphans -join ', ')" }
    if ($cycleSet.Count -gt 0) {
        Write-Host "WARN: $($cycleSet.Count) cycle(s) detected:"
        foreach ($c in $cycleSet) { Write-Host "  $c" }
    }
    Write-Host ''
    Write-Host "Top callers:"
    foreach ($n in ($nodes | Sort-Object { -[int]$_.outDegree } | Select-Object -First 5)) {
        Write-Host "  $($n.id) (out=$($n.outDegree), in=$($n.inDegree))"
    }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
