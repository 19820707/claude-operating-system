# verify-components.ps1 — component-manifest.json coverage + strict/release vs experimental/deprecated
#   pwsh ./tools/verify-components.ps1 [-Json] [-Strict]   # -Strict fails if strict/release surfaces hit experimental/deprecated without allowlist

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

function Fail {
    param([string]$Message)
    [void]$script:failures.Add($Message)
}

function Get-MemberKey {
    param([object]$M)
    $k = [string]$M.kind
    switch ($k) {
        'tool' { return "tool:$([string]$M.id)" }
        'shell' { return "shell:$([string]$M.id)" }
        'skill' { return "skill:$([string]$M.id)" }
        'playbook' { return "playbook:$([string]$M.id)" }
        'policy' { return "policy:$(([string]$M.path).ToLowerInvariant())" }
        'manifest' { return "manifest:$(([string]$M.path).ToLowerInvariant())" }
        'gateValidator' { return "gateValidator:$([string]$M.gateId)/$([string]$M.validatorId)" }
        default { return "unknown:$k" }
    }
}

function Get-OsValidateToolPaths {
    param([string]$Root)
    $p = Join-Path $Root 'tools/os-validate.ps1'
    $raw = Get-Content -LiteralPath $p -Raw
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($raw, "['\`"]tools/[A-Za-z0-9._-]+\.ps1['\`"]")) {
        $s = $m.Value.Trim('''"')
        [void]$set.Add(($s -replace '\\', '/').ToLowerInvariant())
    }
    return @($set)
}

try {
    $cmPath = Join-Path $RepoRoot 'component-manifest.json'
    if (-not (Test-Path -LiteralPath $cmPath)) { throw 'missing component-manifest.json' }
    $cm = Get-Content -LiteralPath $cmPath -Raw | ConvertFrom-Json

    $sm = Get-Content -LiteralPath (Join-Path $RepoRoot 'script-manifest.json') -Raw | ConvertFrom-Json
    $pathToToolId = @{}
    foreach ($t in @($sm.tools)) {
        $rel = ([string]$t.path) -replace '\\', '/'
        $pathToToolId[$rel.ToLowerInvariant()] = [string]$t.id
    }

    $memberToComponent = @{}
    foreach ($c in @($cm.components)) {
        $cid = [string]$c.id
        foreach ($m in @($c.members | ForEach-Object { $_ })) {
            $key = Get-MemberKey -M $m
            if ($memberToComponent.ContainsKey($key)) {
                Fail "duplicate member $key in components '$($memberToComponent[$key])' and '$cid'"
            }
            else {
                $memberToComponent[$key] = $cid
            }
        }
    }

    $universe = [System.Collections.Generic.List[string]]::new()
    foreach ($t in @($sm.tools)) { [void]$universe.Add("tool:$([string]$t.id)") }
    if ($sm.PSObject.Properties.Name -contains 'shellScripts') {
        foreach ($s in @($sm.shellScripts)) { [void]$universe.Add("shell:$([string]$s.id)") }
    }

    $sk = Get-Content -LiteralPath (Join-Path $RepoRoot 'skills-manifest.json') -Raw | ConvertFrom-Json
    foreach ($x in @($sk.skills)) { [void]$universe.Add("skill:$([string]$x.id)") }

    $pb = Get-Content -LiteralPath (Join-Path $RepoRoot 'playbook-manifest.json') -Raw | ConvertFrom-Json
    foreach ($x in @($pb.playbooks)) { [void]$universe.Add("playbook:$([string]$x.id)") }

    $polDir = Join-Path $RepoRoot 'policies'
    if (Test-Path -LiteralPath $polDir) {
        foreach ($f in Get-ChildItem -LiteralPath $polDir -Filter '*.md' -File) {
            [void]$universe.Add("policy:$('policies/' + $f.Name)".ToLowerInvariant())
        }
    }

    $manifestPaths = @(
        'os-manifest.json', 'bootstrap-manifest.json', 'skills-manifest.json', 'docs-index.json',
        'os-capabilities.json', 'capability-manifest.json', 'workflow-manifest.json', 'agent-adapters-manifest.json',
        'runtime-budget.json', 'context-budget.json', 'script-manifest.json', 'playbook-manifest.json',
        'recipe-manifest.json', 'deprecation-manifest.json', 'runtime-profiles.json', 'component-manifest.json',
        'session-memory-manifest.json', 'upgrade-manifest.json'
    )
    foreach ($rel in $manifestPaths) {
        [void]$universe.Add("manifest:$($rel.ToLowerInvariant())")
    }
    $qg = Join-Path $RepoRoot 'quality-gates'
    if (Test-Path -LiteralPath $qg) {
        foreach ($gf in Get-ChildItem -LiteralPath $qg -Filter '*.json' -File) {
            [void]$universe.Add("manifest:$('quality-gates/' + $gf.Name)".ToLowerInvariant())
            $g = Get-Content -LiteralPath $gf.FullName -Raw | ConvertFrom-Json
            $gid = [string]$g.id
            foreach ($v in @($g.requiredValidators)) {
                [void]$universe.Add("gateValidator:$gid/$([string]$v.id)")
            }
        }
    }

    foreach ($u in @($universe | Sort-Object -Unique)) {
        if (-not $memberToComponent.ContainsKey($u)) {
            Fail "universe item not mapped to any component: $u"
        }
    }

    $compMaturity = @{}
    foreach ($c in @($cm.components)) { $compMaturity[[string]$c.id] = [string]$c.maturity }

    function Resolve-ToolComponent {
        param([string]$ToolId)
        $key = "tool:$ToolId"
        if (-not $memberToComponent.ContainsKey($key)) { return $null }
        return $memberToComponent[$key]
    }

    function Test-SurfaceTool {
        param(
            [string]$ToolId,
            [string]$Context,
            [ValidateSet('release', 'orchestrator')]
            [string]$Severity
        )
        $compId = Resolve-ToolComponent -ToolId $ToolId
        if (-not $compId) {
            Fail "$Context tool '$ToolId' not in component manifest"
            return
        }
        $mat = $compMaturity[$compId]
        if ($mat -notin @('experimental', 'deprecated')) { return }
        $allowT = @()
        $allowC = @()
        if ($cm.strictReleaseExperimentalAllowlist) {
            $allowT = @($cm.strictReleaseExperimentalAllowlist.toolIds | ForEach-Object { [string]$_ })
            $allowC = @($cm.strictReleaseExperimentalAllowlist.componentIds | ForEach-Object { [string]$_ })
        }
        if ($allowT -contains $ToolId -or $allowC -contains $compId) {
            [void]$findings.Add([ordered]@{ context = $Context; toolId = $ToolId; componentId = $compId; maturity = $mat; allowlisted = $true })
            return
        }
        $msg = "$Context surface uses $mat component '$compId' (tool $ToolId) — not allowlisted in strictReleaseExperimentalAllowlist"
        $failNow = ($Severity -eq 'release') -or ($Severity -eq 'orchestrator' -and $Strict)
        if ($failNow) { Fail $msg }
        else { [void]$warnings.Add($msg) }
        [void]$findings.Add([ordered]@{ context = $Context; toolId = $ToolId; componentId = $compId; maturity = $mat; allowlisted = $false })
    }

    $releasePath = Join-Path $RepoRoot 'quality-gates/release.json'
    if (Test-Path -LiteralPath $releasePath) {
        $rg = Get-Content -LiteralPath $releasePath -Raw | ConvertFrom-Json
        foreach ($v in @($rg.requiredValidators)) {
            $scr = ([string]$v.script) -replace '\\', '/'
            $tid = $pathToToolId[$scr.ToLowerInvariant()]
            if (-not $tid) {
                Fail "release gate validator script not found in script-manifest: $scr"
            }
            else {
                Test-SurfaceTool -ToolId $tid -Context 'release-gate' -Severity 'release'
            }
        }
    }

    foreach ($rel in (Get-OsValidateToolPaths -Root $RepoRoot)) {
        $tid = $pathToToolId[$rel]
        if (-not $tid) {
            [void]$warnings.Add("os-validate.ps1 references $rel not listed in script-manifest (strict surface check skipped)")
            continue
        }
        Test-SurfaceTool -ToolId $tid -Context 'os-validate-orchestrator' -Severity 'orchestrator'
    }

    [void]$checks.Add([ordered]@{
            name   = 'component-coverage'
            status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' })
            detail = 'all entities mapped; strict/release surfaces vs experimental/deprecated'
        })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-components' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "verify-components: $($env.status)$(if ($Strict) { ' (strict surfaces)' })"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
