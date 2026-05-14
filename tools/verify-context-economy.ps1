# verify-context-economy.ps1 — Size bounds for CLAUDE.md, AGENTS.md, SKILL.md files
#   pwsh ./tools/verify-context-economy.ps1 [-Json]

[CmdletBinding()]
param(
    [switch]$Json
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

try {
    $cfgPath = Join-Path $RepoRoot 'context-budget.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { throw 'missing context-budget.json' }
    $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json

    function Test-ContextEconomyFile {
        param([string]$Rel, [hashtable]$MaxB, [hashtable]$MaxL)
        $p = Join-Path $RepoRoot $Rel
        if (-not (Test-Path -LiteralPath $p)) { return }
        $raw = Get-Content -LiteralPath $p -Raw
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($raw)
        $lines = @($raw -split "`n").Count
        $leaf = Split-Path $Rel -Leaf
        $mb = [int]$MaxB[$leaf]
        $ml = [int]$MaxL[$leaf]
        if ($bytes -gt $mb) {
            [void]$failures.Add("$Rel exceeds maxBytes ($bytes > $mb)")
        }
        elseif ($bytes -gt [int]($mb * 0.85)) {
            [void]$warnings.Add("$Rel approaching maxBytes ($bytes / $mb)")
        }
        if ($lines -gt $ml) {
            [void]$failures.Add("$Rel exceeds maxLines ($lines > $ml)")
        }
        elseif ($lines -gt [int]($ml * 0.9)) {
            [void]$warnings.Add("$Rel approaching maxLines ($lines / $ml)")
        }
        [void]$findings.Add([ordered]@{
                file = $Rel
                bytes = $bytes
                lines = $lines
                maxBytes = $mb
                maxLines = $ml
                severity = $(if ($bytes -gt $mb -or $lines -gt $ml) { 'fail' } elseif ($bytes -gt $mb * 0.85 -or $lines -gt $ml * 0.9) { 'warn' } else { 'ok' })
            })
    }

    $maxB = @{}
    $cfg.maxBytes.PSObject.Properties | ForEach-Object { $maxB[$_.Name] = [int]$_.Value }
    $maxL = @{}
    $cfg.maxLines.PSObject.Properties | ForEach-Object { $maxL[$_.Name] = [int]$_.Value }

    Test-ContextEconomyFile -Rel 'CLAUDE.md' -MaxB $maxB -MaxL $maxL
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'AGENTS.md')) {
        Test-ContextEconomyFile -Rel 'AGENTS.md' -MaxB $maxB -MaxL $maxL
    }

    $glob = [string]$cfg.skillGlob
    if (-not [string]::IsNullOrWhiteSpace($glob)) {
        $g = $glob -replace '/', [char][System.IO.Path]::DirectorySeparatorChar
        $parent = Split-Path (Join-Path $RepoRoot $g) -Parent
        $filter = Split-Path (Join-Path $RepoRoot $g) -Leaf
        if (Test-Path -LiteralPath $parent) {
            foreach ($sk in Get-ChildItem -LiteralPath $parent -Filter $filter -File -ErrorAction SilentlyContinue) {
                $rel = $sk.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
                Test-ContextEconomyFile -Rel $rel -MaxB $maxB -MaxL $maxL
            }
        }
    }

    $claudePath = Join-Path $RepoRoot 'CLAUDE.md'
    if (Test-Path -LiteralPath $claudePath) {
        $rawC = Get-Content -LiteralPath $claudePath -Raw
        $paras = @($rawC -split "`n`n+" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 200 })
        $grp = $paras | Group-Object | Where-Object { $_.Count -ge 3 }
        if ($grp) {
            [void]$warnings.Add('CLAUDE.md contains repeated long paragraphs (possible policy duplication); prefer linking policies/*.md')
            foreach ($g in @($grp | Select-Object -First 3)) {
                [void]$findings.Add([ordered]@{
                        file     = 'CLAUDE.md'
                        bytes    = 0
                        lines    = 0
                        maxBytes = 0
                        maxLines = 0
                        severity = 'warn'
                        detail   = "duplicate paragraph count=$($g.Count) chars~$($g.Name.Length)"
                    })
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'context-files'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'CLAUDE/AGENTS/SKILL sizes' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-context-economy' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-context-economy: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
