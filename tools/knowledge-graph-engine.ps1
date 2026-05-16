# knowledge-graph-engine.ps1 — Semantic knowledge graph over heuristics
# Builds a queryable graph from heuristics/operational.md with tags, files, co-occurrence.
#   pwsh ./tools/knowledge-graph-engine.ps1 -Mode build
#   pwsh ./tools/knowledge-graph-engine.ps1 -Mode query -Query tools/os-validate.ps1
#   pwsh ./tools/knowledge-graph-engine.ps1 -Mode enrich
#   pwsh ./tools/knowledge-graph-engine.ps1 -Mode export-context -Files tools/os-validate.ps1
#   pwsh ./tools/knowledge-graph-engine.ps1 -Mode build -Json

param(
    [ValidateSet('build', 'query', 'enrich', 'export-context')]
    [string]$Mode = 'build',
    [string]$Query = '',
    [string[]]$Files = @(),
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

$graphPath      = Join-Path $RepoRoot '.claude/knowledge-graph.json'
$heuristicsPath = Join-Path $RepoRoot '.claude/heuristics/operational.md'
$decisionLog    = Join-Path $RepoRoot '.claude/decision-log.jsonl'

# Known technology tags to extract from heuristic text
$techTags = @('docker', 'nginx', 'powershell', 'bash', 'git', 'node', 'typescript', 'react', 'vite',
              'postgresql', 'redis', 'prisma', 'nextjs', 'auth', 'jwt', 'csrf', 'cors', 'ci',
              'github', 'vercel', 'aws', 'database', 'migration', 'deploy', 'webhook', 'env')

function Extract-Tags {
    param([string]$Text)
    $lower = $Text.ToLower()
    $found = @($techTags | Where-Object { $lower -match "\b$_\b" })
    return @($found | Sort-Object -Unique)
}

function Extract-Files {
    param([string]$Text)
    # Match paths like tools/foo.ps1, src/auth.ts, Dockerfile, .env, etc.
    $matches = [regex]::Matches($Text, '(?<![`''"])[\w./\\-]+\.(?:ps1|ts|js|sh|json|md|env|yml|yaml|toml|cfg|conf|sql|py|go|rb|tsx|jsx|Dockerfile)[^\s,;)]*')
    return @($matches | ForEach-Object { $_.Value.Trim('.', ',', ';', ')') } | Sort-Object -Unique)
}

function Load-Graph {
    if (Test-Path -LiteralPath $graphPath) {
        try { return (Get-Content -LiteralPath $graphPath -Raw -Encoding utf8) | ConvertFrom-Json }
        catch { }
    }
    return [ordered]@{ schemaVersion = 1; nodes = @(); edges = @(); built = '' }
}

function Save-Graph {
    param($Graph)
    $Graph | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $graphPath -Encoding utf8
}

$findings = [ordered]@{ mode = $Mode }

# ── Mode: build ───────────────────────────────────────────────────────────────
if ($Mode -eq 'build') {
    if (-not (Test-Path -LiteralPath $heuristicsPath)) {
        [void]$warnings.Add("heuristics/operational.md not found at $heuristicsPath")
        [void]$checks.Add([ordered]@{ name = 'build'; status = 'warn'; detail = 'missing heuristics file' })
    } else {
        $src = Get-Content -LiteralPath $heuristicsPath -Raw -Encoding utf8
        $nodes = [System.Collections.Generic.List[object]]::new()

        # Parse each ### H<n> — Title block
        $headerMatches = [regex]::Matches($src, '(?m)^###\s+(H[\w-]+)\s+[—–-]+\s+(.+)$')

        foreach ($hm in $headerMatches) {
            $id    = $hm.Groups[1].Value
            $title = $hm.Groups[2].Value.Trim()

            # Extract block content between this header and the next
            $start = $hm.Index + $hm.Length
            $nextIdx = $src.IndexOf("`n###", $start)
            $block = if ($nextIdx -gt $start) { $src.Substring($start, $nextIdx - $start) } else { $src.Substring($start) }

            # Extract structured fields
            $evidMatch = [regex]::Match($block, '(?m)^\*\*Evidence:\*\*\s*(.+?)(?=^\*\*|\z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $ruleMatch  = [regex]::Match($block, '(?m)^\*\*Rule:\*\*\s*(.+?)(?=^\*\*|\z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            $applyMatch = [regex]::Match($block, '(?m)^\*\*Apply:\*\*\s*(.+?)(?=^\*\*|\z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)

            $evidence = if ($evidMatch.Success) { $evidMatch.Groups[1].Value.Trim() } else { '' }
            $rule     = if ($ruleMatch.Success)  { $ruleMatch.Groups[1].Value.Trim()  } else { $title }
            $apply    = if ($applyMatch.Success) { $applyMatch.Groups[1].Value.Trim() } else { '' }

            $fullText = "$title $evidence $rule $apply $block"
            $tags  = Extract-Tags  -Text $fullText
            $files = Extract-Files -Text $fullText

            [void]$nodes.Add([ordered]@{
                id         = $id
                type       = 'heuristic'
                title      = $title
                rule       = $rule
                evidence   = $evidence
                apply      = $apply
                tags       = @($tags)
                files      = @($files)
                confidence = 1.0
                coOccurs   = [ordered]@{}
            })
        }

        $graph = [ordered]@{
            schemaVersion = 1
            built         = (Get-Date).ToUniversalTime().ToString('o')
            nodes         = @($nodes)
            edges         = @()
        }
        if (-not $DryRun) { Save-Graph -Graph $graph }
        [void]$checks.Add([ordered]@{ name = 'build'; status = 'ok'; detail = "$($nodes.Count) heuristics parsed$(if ($DryRun) { ' (dry-run)' })" })
        $findings.nodesBuilt = $nodes.Count
    }
}

# ── Mode: enrich ──────────────────────────────────────────────────────────────
elseif ($Mode -eq 'enrich') {
    $graph = Load-Graph
    if (-not (Test-Path -LiteralPath $decisionLog)) {
        [void]$warnings.Add('decision-log.jsonl not found — nothing to enrich from')
        [void]$checks.Add([ordered]@{ name = 'enrich'; status = 'warn'; detail = 'no decision log' })
    } else {
        $lines = Get-Content -LiteralPath $decisionLog -Encoding utf8
        $heuristicRefs = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            if (-not $line.Trim()) { continue }
            try {
                $r = $line | ConvertFrom-Json
                $text = ($r | ConvertTo-Json -Compress -Depth 4)
                $matches = [regex]::Matches($text, '\bH\d+\b')
                foreach ($m in $matches) { [void]$heuristicRefs.Add($m.Value) }
            } catch { }
        }

        # Update co-occurrence weights
        $nodes = [System.Collections.Generic.List[object]]::new()
        foreach ($n in @($graph.nodes)) { [void]$nodes.Add($n) }

        $grouped = $heuristicRefs | Group-Object | ForEach-Object { [ordered]@{ id = $_.Name; count = $_.Count } }
        foreach ($ref in $grouped) {
            $node = @($nodes | Where-Object { [string]$_.id -eq [string]$ref.id }) | Select-Object -First 1
            if ($node) { $node.confidence = [Math]::Min(1.0, [double]$node.confidence + [double]$ref.count * 0.05) }
        }

        $graph.nodes = @($nodes)
        $graph.enriched = (Get-Date).ToUniversalTime().ToString('o')
        Save-Graph -Graph $graph
        [void]$checks.Add([ordered]@{ name = 'enrich'; status = 'ok'; detail = "$($heuristicRefs.Count) references processed" })
        $findings.refsProcessed = $heuristicRefs.Count
    }
}

# ── Mode: query ───────────────────────────────────────────────────────────────
elseif ($Mode -eq 'query') {
    $graph = Load-Graph
    if (-not $graph.nodes -or @($graph.nodes).Count -eq 0) {
        [void]$warnings.Add('Graph is empty — run --build first')
        [void]$checks.Add([ordered]@{ name = 'query'; status = 'warn'; detail = 'empty graph' })
    } else {
        $queryLower  = $Query.ToLower()
        $queryName   = [System.IO.Path]::GetFileName($Query)
        $queryTags   = Extract-Tags -Text $Query

        $scored = [System.Collections.Generic.List[object]]::new()
        foreach ($n in @($graph.nodes)) {
            $score = 0.0
            # Tag overlap
            foreach ($t in @($n.tags)) { if ($queryLower -match "\b$t\b" -or $queryTags -contains $t) { $score += 0.3 } }
            # File mention overlap
            foreach ($file in @($n.files)) { if ($queryLower -contains [System.IO.Path]::GetFileName($file).ToLower() -or $Query -match [regex]::Escape($file)) { $score += 0.5 } }
            # Confidence boost
            $score *= [double]$n.confidence

            if ($score -gt 0) {
                [void]$scored.Add([ordered]@{ id = $n.id; title = $n.title; rule = $n.rule; score = [Math]::Round($score, 3) })
            }
        }
        $top5 = @($scored | Sort-Object { -[double]$_.score } | Select-Object -First 5)
        [void]$checks.Add([ordered]@{ name = 'query'; status = 'ok'; detail = "$($top5.Count) matches" })
        $findings.query   = $Query
        $findings.results = @($top5)

        if (-not $Json) {
            Write-Host "knowledge-graph-engine [query: $Query]"
            foreach ($r in $top5) {
                Write-Host "  [$($r.id)] ($($r.score)) $($r.title)"
                Write-Host "       $($r.rule)"
            }
        }
    }
}

# ── Mode: export-context ──────────────────────────────────────────────────────
elseif ($Mode -eq 'export-context') {
    $graph = Load-Graph
    $contextBlocks = [System.Collections.Generic.List[string]]::new()

    foreach ($f in $Files) {
        $fname = [System.IO.Path]::GetFileName($f)
        $ftags = Extract-Tags -Text $f

        $scored = [System.Collections.Generic.List[object]]::new()
        foreach ($n in @($graph.nodes)) {
            $score = 0.0
            foreach ($t in @($n.tags)) { if ($f.ToLower() -match "\b$t\b" -or $ftags -contains $t) { $score += 0.3 } }
            foreach ($nf in @($n.files)) { if ($fname -match [regex]::Escape([System.IO.Path]::GetFileName($nf))) { $score += 0.5 } }
            $score *= [double]$n.confidence
            if ($score -gt 0) { [void]$scored.Add([ordered]@{ n = $n; score = $score }) }
        }

        $top3 = @($scored | Sort-Object { -[double]$_.score } | Select-Object -First 3)
        foreach ($s in $top3) {
            $h = $s.n
            [void]$contextBlocks.Add("**[$($h.id)]** $($h.title)
Rule: $($h.rule)")
        }
    }

    $contextMd = if ($contextBlocks.Count -gt 0) {
        "## Relevant Heuristics`n`n" + ($contextBlocks | Select-Object -Unique | Join-String -Separator "`n`n")
    } else {
        "## Relevant Heuristics`n`n_(none matched — run knowledge-graph-engine --build first)_"
    }

    [void]$checks.Add([ordered]@{ name = 'export-context'; status = 'ok'; detail = "$($contextBlocks.Count) heuristic(s) for $($Files.Count) file(s)" })
    $findings.context = $contextMd
    $findings.files   = @($Files)

    if (-not $Json) { Write-Host $contextMd }
}

$sw.Stop()
$st = if ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'knowledge-graph-engine' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @() `
    -Findings @(@($findings))

if ($Json) { $env | ConvertTo-Json -Depth 12 -Compress | Write-Output }
exit 0
