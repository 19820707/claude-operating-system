# run-contract-tests.ps1 — Cross-manifest, docs, and script contract checks
#   pwsh ./tools/run-contract-tests.ps1 [-Json]
# Keep aligned with verify-json-contracts.ps1 manifest↔schema pairs when adding root manifests.

[CmdletBinding()]
param([switch]$Json)

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

function Test-FileExists {
    param([string]$RelFromRepoRoot, [string]$Ctx)
    $n = $RelFromRepoRoot -replace '\\', '/'
    $full = Join-Path $RepoRoot ($n -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full)) {
        Fail "$Ctx missing file: $n"
        return $false
    }
    return $true
}

function Get-PlaybookIds {
    param([string]$Root)
    $p = Join-Path $Root 'playbook-manifest.json'
    $pb = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
    $ids = @{}
    foreach ($x in @($pb.playbooks)) { $ids[[string]$x.id] = $true }
    return $ids
}

function Get-SkillDirs {
    param([string]$Root)
    $rootDir = Join-Path $Root 'source/skills'
    if (-not (Test-Path -LiteralPath $rootDir)) { return @{} }
    $h = @{}
    Get-ChildItem -LiteralPath $rootDir -Directory | ForEach-Object { $h[$_.Name] = $true }
    return $h
}

function Get-ScriptManifestMap {
    param([string]$Root)
    $mf = Get-Content -LiteralPath (Join-Path $Root 'script-manifest.json') -Raw | ConvertFrom-Json
    $byPath = @{}
    foreach ($t in @($mf.tools)) {
        $rel = ([string]$t.path) -replace '\\', '/'
        $byPath[$rel.ToLowerInvariant()] = $t
    }
    return $byPath
}

function Get-OsValidateToolRefs {
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
    # --- 1) script-manifest paths exist ---
    $sm = Get-Content -LiteralPath (Join-Path $RepoRoot 'script-manifest.json') -Raw | ConvertFrom-Json
    foreach ($t in @($sm.tools)) {
        $rel = ([string]$t.path) -replace '\\', '/'
        $null = Test-FileExists -RelFromRepoRoot $rel -Ctx 'script-manifest'
    }

    # --- 2) os-manifest entrypoints ---
    $om = Get-Content -LiteralPath (Join-Path $RepoRoot 'os-manifest.json') -Raw | ConvertFrom-Json
    foreach ($ep in $om.entrypoints.PSObject.Properties) {
        $rel = ([string]$ep.Value) -replace '\\', '/'
        if ($rel -match '^tools/') { $null = Test-FileExists -RelFromRepoRoot $rel -Ctx "os-manifest.entrypoints.$($ep.Name)" }
    }

    # --- 3) manifest ↔ schema (same set as verify-json-contracts + deprecation) ---
    $pairs = [ordered]@{
        'os-manifest.json'                     = 'schemas/os-manifest.schema.json'
        'bootstrap-manifest.json'              = 'schemas/bootstrap-manifest.schema.json'
        'skills-manifest.json'                 = 'schemas/skills-manifest.schema.json'
        'docs-index.json'                      = 'schemas/docs-index.schema.json'
        'invariants-manifest.json'             = 'schemas/invariants-manifest.schema.json'
        'os-capabilities.json'                 = 'schemas/os-capabilities.schema.json'
        'capability-manifest.json'             = 'schemas/capability-manifest.schema.json'
        'workflow-manifest.json'               = 'schemas/workflow-manifest.schema.json'
        'agent-adapters-manifest.json'         = 'schemas/agent-adapters.schema.json'
        'runtime-budget.json'                  = 'schemas/runtime-budget.schema.json'
        'context-budget.json'                  = 'schemas/context-budget.schema.json'
        'script-manifest.json'                 = 'schemas/script-manifest.schema.json'
        'playbook-manifest.json'               = 'schemas/playbook-manifest.schema.json'
        'recipe-manifest.json'                 = 'schemas/recipe-manifest.schema.json'
        'deprecation-manifest.json'            = 'schemas/deprecation-manifest.schema.json'
        'component-manifest.json'              = 'schemas/component-manifest.schema.json'
        'compatibility-manifest.json'          = 'schemas/compatibility-manifest.schema.json'
        'lifecycle-manifest.json'              = 'schemas/lifecycle-manifest.schema.json'
        'distribution-manifest.json'           = 'schemas/distribution-manifest.schema.json'
        'upgrade-manifest.json'                = 'schemas/upgrade-manifest.schema.json'
    }
    foreach ($k in $pairs.Keys) {
        $null = Test-FileExists -RelFromRepoRoot $k -Ctx 'manifest'
        $null = Test-FileExists -RelFromRepoRoot $pairs[$k] -Ctx 'schema'
    }
    $qgDir = Join-Path $RepoRoot 'quality-gates'
    if (Test-Path -LiteralPath $qgDir) {
        foreach ($qg in Get-ChildItem -LiteralPath $qgDir -Filter '*.json' -File) {
            $rel = 'quality-gates/' + $qg.Name
            $null = Test-FileExists -RelFromRepoRoot $rel -Ctx 'quality-gate'
            $null = Test-FileExists -RelFromRepoRoot 'schemas/quality-gate.schema.json' -Ctx 'quality-gate-schema'
        }
    }

    # --- 4) Documented pwsh commands (README + docs + recipes + INDEX) ---
    $docScan = @(
        'README.md',
        'INDEX.md'
    ) + @(
        Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'docs') -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object { 'docs/' + $_.Name }
    ) + @(
        Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'recipes') -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object { 'recipes/' + $_.Name }
    )
    foreach ($rel in $docScan) {
        $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $body = Get-Content -LiteralPath $full -Raw
        foreach ($m in [regex]::Matches($body, '(?im)(?:^|\n)\s*(?:pwsh|powershell)[^\n]*?(tools/[A-Za-z0-9._/-]+\.ps1)')) {
            $tool = $m.Groups[1].Value -replace '\\', '/'
            $null = Test-FileExists -RelFromRepoRoot $tool -Ctx "documented command in $rel"
        }
    }

    # --- 5) Capabilities: skills + playbooks ---
    $skillNames = Get-SkillDirs -Root $RepoRoot
    $playIds = Get-PlaybookIds -Root $RepoRoot

    $cap = Get-Content -LiteralPath (Join-Path $RepoRoot 'os-capabilities.json') -Raw | ConvertFrom-Json
    foreach ($c in @($cap.capabilities)) {
        $sk = [string]$c.skill
        if (-not $skillNames.ContainsKey($sk)) {
            Fail "os-capabilities skill '$sk' ($($c.id)) missing under source/skills/"
        }
        foreach ($line in @(@($c.validations | ForEach-Object { [string]$_ }) + @([string]$c.entrypoint))) {
            if ($line -notmatch '(?i)pwsh|powershell') { continue }
            foreach ($m in [regex]::Matches($line, 'tools/[A-Za-z0-9._/-]+\.ps1')) {
                $tool = $m.Value -replace '\\', '/'
                $null = Test-FileExists -RelFromRepoRoot $tool -Ctx "os-capabilities $($c.id)"
            }
        }
    }

    $cm = Get-Content -LiteralPath (Join-Path $RepoRoot 'capability-manifest.json') -Raw | ConvertFrom-Json
    foreach ($r in @($cm.routes)) {
        foreach ($sk in @($r.relevantSkills | ForEach-Object { [string]$_ })) {
            if (-not $skillNames.ContainsKey($sk)) {
                Fail "capability-manifest route $($r.id) references unknown skill '$sk'"
            }
        }
        foreach ($pb in @($r.relevantPlaybooks | ForEach-Object { [string]$_ })) {
            if (-not $playIds.ContainsKey($pb)) {
                Fail "capability-manifest route $($r.id) references unknown playbook id '$pb'"
            }
        }
        foreach ($vline in @($r.validators | ForEach-Object { [string]$_ })) {
            foreach ($m in [regex]::Matches($vline, 'tools/[A-Za-z0-9._/-]+\.ps1')) {
                $tool = $m.Value -replace '\\', '/'
                $null = Test-FileExists -RelFromRepoRoot $tool -Ctx "capability-manifest route $($r.id) validators"
            }
        }
    }

    # --- 6) Quality gate validators ---
    foreach ($qg in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'quality-gates') -Filter '*.json' -File) {
        $gate = Get-Content -LiteralPath $qg.FullName -Raw | ConvertFrom-Json
        foreach ($v in @($gate.requiredValidators)) {
            $scr = ([string]$v.script) -replace '\\', '/'
            $null = Test-FileExists -RelFromRepoRoot $scr -Ctx "quality-gate $($gate.id).$($v.id)"
        }
    }

    # --- 7) Generated targets ↔ canonical source (agent adapters manifest) ---
    $aa = Get-Content -LiteralPath (Join-Path $RepoRoot 'agent-adapters-manifest.json') -Raw | ConvertFrom-Json
    if ($aa.generatedTargets) {
        foreach ($gt in @($aa.generatedTargets)) {
            $src = ([string]$gt.source) -replace '\\', '/'
            $fullSrc = Join-Path $RepoRoot ($src.TrimEnd('/') -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $fullSrc)) {
                Fail "agent-adapters generatedTargets source missing: $src (agent $($gt.agent))"
            }
        }
    }

    # --- 8) Release gate evidence ↔ validators (keyword map) ---
    $mapPath = Join-Path $RepoRoot 'tests/contracts/release-evidence-keywords.json'
    if (-not (Test-Path -LiteralPath $mapPath)) {
        Fail 'tests/contracts/release-evidence-keywords.json missing'
    }
    else {
        $kw = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
        $relGate = Join-Path $RepoRoot ([string]$kw.gateFile)
        $gate = Get-Content -LiteralPath $relGate -Raw | ConvertFrom-Json
        $validatorIds = @{}
        foreach ($v in @($gate.requiredValidators)) { $validatorIds[[string]$v.id] = $true }
        $humanOnly = @()
        if ($kw.PSObject.Properties.Name -contains 'humanOnlyEvidenceSubstrings') {
            $humanOnly = @($kw.humanOnlyEvidenceSubstrings | ForEach-Object { [string]$_ })
        }
        foreach ($ev in @($gate.requiredEvidence | ForEach-Object { [string]$_ })) {
            $el = $ev.ToLowerInvariant()
            $skipHuman = $false
            foreach ($h in $humanOnly) {
                if ($el.Contains($h.ToLowerInvariant())) { $skipHuman = $true; break }
            }
            if ($skipHuman) { continue }
            $matched = $false
            foreach ($row in @($kw.mappings)) {
                $vid = [string]$row.validatorId
                if (-not $validatorIds.ContainsKey($vid)) { continue }
                foreach ($k in @($row.keywords | ForEach-Object { [string]$_ })) {
                    if ($el.Contains($k.ToLowerInvariant())) { $matched = $true; break }
                }
                if ($matched) { break }
            }
            if (-not $matched) {
                Fail "release requiredEvidence not mapped to a declared validator keyword: $ev"
            }
        }
    }

    # --- 9) Strict profile vs experimental / deprecated (script-manifest + allowlist) ---
    $allowPath = Join-Path $RepoRoot 'tests/contracts/strict-profile-allowlist.json'
    if (-not (Test-Path -LiteralPath $allowPath)) {
        Fail 'tests/contracts/strict-profile-allowlist.json missing'
    }
    else {
        $al = Get-Content -LiteralPath $allowPath -Raw | ConvertFrom-Json
        $allowExp = @{}
        foreach ($x in @($al.toolIdsAllowExperimentalInStrictProfile | ForEach-Object { [string]$_ })) { $allowExp[$x] = $true }
        $allowDep = @{}
        foreach ($x in @($al.toolIdsAllowDeprecatedInStrictProfile | ForEach-Object { [string]$_ })) { $allowDep[$x] = $true }
        $byPath = Get-ScriptManifestMap -Root $RepoRoot
        foreach ($rel in (Get-OsValidateToolRefs -Root $RepoRoot)) {
            $t = $byPath[$rel]
            if (-not $t) {
                [void]$warnings.Add("os-validate.ps1 references $rel not listed in script-manifest.json (review)")
                continue
            }
            $mid = [string]$t.id
            $mat = [string]$t.maturity
            if ([string]::IsNullOrWhiteSpace($mat)) { $mat = 'stable' }
            if ($mat -eq 'experimental' -and -not $allowExp.ContainsKey($mid)) {
                Fail "strict profile references experimental tool without allowlist: $mid ($rel)"
            }
            if ($mat -eq 'deprecated' -and -not $allowDep.ContainsKey($mid)) {
                Fail "strict profile references deprecated tool without allowlist: $mid ($rel)"
            }
        }
    }

    # --- Deprecation manifest contract (strict surfaces) ---
    $dep = Join-Path $RepoRoot 'tools/verify-deprecations.ps1'
    $null = & pwsh -NoProfile -File $dep -Json -Strict 2>$null
    if ($LASTEXITCODE -ne 0) {
        Fail 'verify-deprecations.ps1 -Strict failed (deprecated usage on orchestrator or gates)'
    }

    # --- JSON contracts (delegated) ---
    $vj = Join-Path $RepoRoot 'tools/verify-json-contracts.ps1'
    $null = & pwsh -NoProfile -File $vj 2>$null
    if ($LASTEXITCODE -ne 0) {
        Fail 'verify-json-contracts.ps1 failed'
    }

    [void]$checks.Add([ordered]@{ name = 'contract-tests'; status = 'ok'; detail = 'manifests, docs commands, capabilities, gates, adapters, release evidence, strict maturity' })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'run-contract-tests' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "run-contract-tests: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
