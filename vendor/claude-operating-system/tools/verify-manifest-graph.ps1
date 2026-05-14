# verify-manifest-graph.ps1 — Cross-manifest structural consistency (dead paths, schema pairs, gate validators, release maturity)
#   pwsh ./tools/verify-manifest-graph.ps1 [-Json] [-Strict]

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

function Fail { param([string]$m) [void]$script:failures.Add($m) }

$manifestPairs = @{
    'os-manifest.json'                        = 'schemas/os-manifest.schema.json'
    'bootstrap-manifest.json'               = 'schemas/bootstrap-manifest.schema.json'
    'skills-manifest.json'                  = 'schemas/skills-manifest.schema.json'
    'docs-index.json'                       = 'schemas/docs-index.schema.json'
    'invariants-manifest.json'              = 'schemas/invariants-manifest.schema.json'
    'os-capabilities.json'                  = 'schemas/os-capabilities.schema.json'
    'capability-manifest.json'              = 'schemas/capability-manifest.schema.json'
    'workflow-manifest.json'                = 'schemas/workflow-manifest.schema.json'
    'agent-adapters-manifest.json'          = 'schemas/agent-adapters.schema.json'
    'runtime-budget.json'                   = 'schemas/runtime-budget.schema.json'
    'gate-status-contract.json'             = 'schemas/gate-result.schema.json'
    'policies/autonomy-policy.json'         = 'schemas/autonomy-policy.schema.json'
    'context-budget.json'                   = 'schemas/context-budget.schema.json'
    'script-manifest.json'                  = 'schemas/script-manifest.schema.json'
    'playbook-manifest.json'                = 'schemas/playbook-manifest.schema.json'
    'recipe-manifest.json'                  = 'schemas/recipe-manifest.schema.json'
    'deprecation-manifest.json'             = 'schemas/deprecation-manifest.schema.json'
    'component-manifest.json'               = 'schemas/component-manifest.schema.json'
    'compatibility-manifest.json'           = 'schemas/compatibility-manifest.schema.json'
    'lifecycle-manifest.json'               = 'schemas/lifecycle-manifest.schema.json'
    'distribution-manifest.json'            = 'schemas/distribution-manifest.schema.json'
    'upgrade-manifest.json'                 = 'schemas/upgrade-manifest.schema.json'
}

try {
    foreach ($pair in $manifestPairs.GetEnumerator() | Sort-Object Name) {
        $j = Join-Path $RepoRoot $pair.Key
        $s = Join-Path $RepoRoot $pair.Value
        if (-not (Test-Path -LiteralPath $j)) { Fail "missing JSON: $($pair.Key)"; continue }
        if (-not (Test-Path -LiteralPath $s)) { Fail "missing schema for $($pair.Key): $($pair.Value)"; continue }
    }
    [void]$checks.Add([ordered]@{ name = 'json_schema_pairs'; status = 'ok'; detail = 'manifest and schema file pairs exist' })

    $smPath = Join-Path $RepoRoot 'script-manifest.json'
    $sm = Get-Content -LiteralPath $smPath -Raw | ConvertFrom-Json
    foreach ($t in @($sm.tools)) {
        $rel = ([string]$t.path) -replace '\\', '/'
        $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { Fail "script-manifest tool missing file: $rel" }
    }
    if ($sm.PSObject.Properties.Name -contains 'shellScripts') {
        foreach ($sh in @($sm.shellScripts)) {
            $rel = ([string]$sh.path) -replace '\\', '/'
            $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $full)) { Fail "script-manifest shellScripts missing: $rel" }
        }
    }
    [void]$checks.Add([ordered]@{ name = 'script_manifest_paths'; status = 'ok'; detail = 'all tool paths resolve' })

    $pathToToolId = @{}
    foreach ($t in @($sm.tools)) {
        $rel = ([string]$t.path) -replace '\\', '/'
        $pathToToolId[$rel.ToLowerInvariant()] = [string]$t.id
    }

    $sk = Get-Content -LiteralPath (Join-Path $RepoRoot 'skills-manifest.json') -Raw | ConvertFrom-Json
    foreach ($x in @($sk.skills)) {
        $p = Join-Path $RepoRoot ([string]$x.path)
        if (-not (Test-Path -LiteralPath $p)) { Fail "skills-manifest missing: $($x.path)" }
    }
    [void]$checks.Add([ordered]@{ name = 'skills_paths'; status = 'ok'; detail = 'skills-manifest paths exist' })

    $pb = Get-Content -LiteralPath (Join-Path $RepoRoot 'playbook-manifest.json') -Raw | ConvertFrom-Json
    foreach ($x in @($pb.playbooks)) {
        if ($x.PSObject.Properties.Name -contains 'path') {
            $p = Join-Path $RepoRoot ([string]$x.path)
            if (-not (Test-Path -LiteralPath $p)) { Fail "playbook-manifest missing: $($x.path)" }
        }
    }
    [void]$checks.Add([ordered]@{ name = 'playbook_paths'; status = 'ok'; detail = 'playbook paths exist' })

    $rm = Get-Content -LiteralPath (Join-Path $RepoRoot 'recipe-manifest.json') -Raw | ConvertFrom-Json
    foreach ($x in @($rm.recipes)) {
        $p = Join-Path $RepoRoot ([string]$x.path)
        if (-not (Test-Path -LiteralPath $p)) { Fail "recipe-manifest missing: $($x.path)" }
    }
    [void]$checks.Add([ordered]@{ name = 'recipe_paths'; status = 'ok'; detail = 'recipe paths exist' })

    $cm = Get-Content -LiteralPath (Join-Path $RepoRoot 'capability-manifest.json') -Raw | ConvertFrom-Json
    foreach ($r in @($cm.routes)) {
        foreach ($line in @($r.validators | ForEach-Object { [string]$_ })) {
            foreach ($m in [regex]::Matches($line, 'tools/[A-Za-z0-9._-]+\.ps1')) {
                $rel = $m.Value
                $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $full)) { Fail "capability route $($r.id) validator missing: $rel" }
            }
        }
    }
    [void]$checks.Add([ordered]@{ name = 'capability_validator_paths'; status = 'ok'; detail = 'capability-manifest tool refs exist' })

    $oc = Get-Content -LiteralPath (Join-Path $RepoRoot 'os-capabilities.json') -Raw | ConvertFrom-Json
    foreach ($c in @($oc.capabilities)) {
        foreach ($line in @($c.validations | ForEach-Object { [string]$_ }) + @([string]$c.entrypoint)) {
            foreach ($m in [regex]::Matches($line, 'tools/[A-Za-z0-9._-]+\.ps1')) {
                $rel = $m.Value
                $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $full)) { Fail "os-capabilities $($c.id) missing: $rel" }
            }
        }
    }
    [void]$checks.Add([ordered]@{ name = 'os_capabilities_paths'; status = 'ok'; detail = 'os-capabilities tool refs exist' })

    $om = Get-Content -LiteralPath (Join-Path $RepoRoot 'os-manifest.json') -Raw | ConvertFrom-Json
    foreach ($p in $om.entrypoints.PSObject.Properties) {
        $rel = [string]$p.Value
        $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { Fail "os-manifest entrypoints.$($p.Name) missing: $rel" }
    }
    foreach ($p in $om.manifests.PSObject.Properties) {
        $rel = [string]$p.Value
        $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { Fail "os-manifest manifests.$($p.Name) missing: $rel" }
    }
    [void]$checks.Add([ordered]@{ name = 'os_manifest_paths'; status = 'ok'; detail = 'entrypoints + manifests exist' })

    $dm = Get-Content -LiteralPath (Join-Path $RepoRoot 'distribution-manifest.json') -Raw | ConvertFrom-Json
    foreach ($f in @($dm.rootFiles | ForEach-Object { [string]$_ })) {
        $full = Join-Path $RepoRoot ($f -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { Fail "distribution-manifest rootFiles missing: $f" }
    }
    foreach ($tr in @($dm.includeTrees)) {
        $rel = [string]$tr.path
        $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { Fail "distribution-manifest includeTrees missing: $rel" }
    }
    [void]$checks.Add([ordered]@{ name = 'distribution_paths'; status = 'ok'; detail = 'distribution pack paths exist' })

    $qgDir = Join-Path $RepoRoot 'quality-gates'
    foreach ($gf in Get-ChildItem -LiteralPath $qgDir -Filter '*.json' -File) {
        $gate = Get-Content -LiteralPath $gf.FullName -Raw | ConvertFrom-Json
        foreach ($v in @($gate.requiredValidators)) {
            $scr = ([string]$v.script) -replace '\\', '/'
            $vf = Join-Path $RepoRoot ($scr -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $vf)) { Fail "quality-gate $($gate.id) validator missing: $scr" }
        }
    }
    [void]$checks.Add([ordered]@{ name = 'quality_gate_scripts'; status = 'ok'; detail = 'quality-gates/*.json scripts exist' })

    $comp = Get-Content -LiteralPath (Join-Path $RepoRoot 'component-manifest.json') -Raw | ConvertFrom-Json
    $compMat = @{}
    foreach ($c in @($comp.components)) { $compMat[[string]$c.id] = [string]$c.maturity }
    $memberToComp = @{}
    foreach ($c in @($comp.components)) {
        foreach ($m in @($c.members | ForEach-Object { $_ })) {
            $k = [string]$m.kind
            $key = switch ($k) {
                'tool' { "tool:$([string]$m.id)" }
                default { $null }
            }
            if ($key) { $memberToComp[$key] = [string]$c.id }
        }
    }
    function Resolve-ToolComponent {
        param([string]$ToolId)
        $key = "tool:$ToolId"
        if (-not $memberToComp.ContainsKey($key)) { return $null }
        return $memberToComp[$key]
    }

    $rgPath = Join-Path $RepoRoot 'quality-gates/release.json'
    if (Test-Path -LiteralPath $rgPath) {
        $rg = Get-Content -LiteralPath $rgPath -Raw | ConvertFrom-Json
        foreach ($v in @($rg.requiredValidators)) {
            $scr = ([string]$v.script) -replace '\\', '/'
            $tid = $pathToToolId[$scr.ToLowerInvariant()]
            if (-not $tid) { Fail "release gate script not in script-manifest: $scr"; continue }
            $cid = Resolve-ToolComponent -ToolId $tid
            if (-not $cid) { Fail "release gate tool '$tid' not mapped in component-manifest"; continue }
            $mat = $compMat[$cid]
            if ($mat -in @('experimental', 'deprecated')) {
                $allowT = @()
                if ($comp.strictReleaseExperimentalAllowlist) {
                    $allowT = @($comp.strictReleaseExperimentalAllowlist.toolIds | ForEach-Object { [string]$_ })
                }
                if ($allowT -notcontains $tid) {
                    Fail "release gate depends on $mat component '$cid' tool '$tid' without strictReleaseExperimentalAllowlist"
                }
            }
        }
    }
    [void]$checks.Add([ordered]@{ name = 'release_maturity'; status = 'ok'; detail = 'release validators not on experimental/deprecated without allowlist' })

    $schGen = Join-Path $RepoRoot 'schemas/generated-target.schema.json'
    if (-not (Test-Path -LiteralPath $schGen)) { Fail 'missing schemas/generated-target.schema.json' }

    [void]$findings.Add([ordered]@{ graphChecks = $checks.Count })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
if ($Strict -and $warnings.Count -gt 0) { $st = 'fail' }
$env = New-OsValidatorEnvelope -Tool 'verify-manifest-graph' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "verify-manifest-graph: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
if ($Strict -and $warnings.Count -gt 0) { exit 1 }
exit 0
