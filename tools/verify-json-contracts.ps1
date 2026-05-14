# verify-json-contracts.ps1 — Validate JSON manifests, schemas, and master references without external deps
# Run from repo root or any cwd:
#   pwsh ./tools/verify-json-contracts.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$failed = $false

function Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Read-JsonFile {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Fail "missing JSON file: $RelativePath"
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    } catch {
        Fail "invalid JSON: $RelativePath"
        return $null
    }
}

function Test-SafeRelativePath {
    param([string]$Path, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail "empty path in $Field"
        return
    }
    if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        Fail "unsafe relative path '$Path' in $Field"
    }
}

function Test-JsonSchemaVersion {
    param([object]$Json, [string]$Name)
    if (-not $Json) { return }
    if (-not ($Json.PSObject.Properties.Name -contains 'schemaVersion')) {
        Fail "$Name missing schemaVersion"
        return
    }
    if ([int]$Json.schemaVersion -lt 1) { Fail "$Name has invalid schemaVersion" }
}

Write-Host 'verify-json-contracts'
Write-Host "Repo: $RepoRoot"
Write-Host ''

$manifestPairs = @{
    'os-manifest.json' = 'schemas/os-manifest.schema.json'
    'bootstrap-manifest.json' = 'schemas/bootstrap-manifest.schema.json'
    'skills-manifest.json' = 'schemas/skills-manifest.schema.json'
    'docs-index.json' = 'schemas/docs-index.schema.json'
    'invariants-manifest.json' = 'schemas/invariants-manifest.schema.json'
    'os-capabilities.json' = 'schemas/os-capabilities.schema.json'
    'capability-manifest.json' = 'schemas/capability-manifest.schema.json'
    'workflow-manifest.json' = 'schemas/workflow-manifest.schema.json'
    'agent-adapters-manifest.json' = 'schemas/agent-adapters.schema.json'
    'runtime-budget.json' = 'schemas/runtime-budget.schema.json'
    'gate-status-contract.json' = 'schemas/gate-result.schema.json'
    'policies/autonomy-policy.json' = 'schemas/autonomy-policy.schema.json'
    'context-budget.json' = 'schemas/context-budget.schema.json'
    'script-manifest.json' = 'schemas/script-manifest.schema.json'
    'playbook-manifest.json' = 'schemas/playbook-manifest.schema.json'
    'recipe-manifest.json' = 'schemas/recipe-manifest.schema.json'
    'deprecation-manifest.json' = 'schemas/deprecation-manifest.schema.json'
    'component-manifest.json' = 'schemas/component-manifest.schema.json'
    'compatibility-manifest.json' = 'schemas/compatibility-manifest.schema.json'
    'lifecycle-manifest.json' = 'schemas/lifecycle-manifest.schema.json'
    'distribution-manifest.json' = 'schemas/distribution-manifest.schema.json'
    'upgrade-manifest.json' = 'schemas/upgrade-manifest.schema.json'
}

foreach ($pair in $manifestPairs.GetEnumerator() | Sort-Object Name) {
    $json = Read-JsonFile -RelativePath $pair.Key
    $schema = Read-JsonFile -RelativePath $pair.Value
    Test-JsonSchemaVersion -Json $json -Name $pair.Key
    if (-not $schema) { continue }
    if (-not ($schema.PSObject.Properties.Name -contains '$schema')) { Fail "$($pair.Value) missing `$schema declaration" }
    Write-Host "OK:  $($pair.Key) + $($pair.Value)"
}

$qgDir = Join-Path $RepoRoot 'quality-gates'
$qgSchema = 'schemas/quality-gate.schema.json'
if (Test-Path -LiteralPath $qgDir) {
    $schQ = Read-JsonFile -RelativePath $qgSchema
    if (-not $schQ) { }
    elseif (-not ($schQ.PSObject.Properties.Name -contains '$schema')) { Fail "$qgSchema missing `$schema declaration" }
    else {
        foreach ($qg in Get-ChildItem -LiteralPath $qgDir -Filter '*.json' -File | Sort-Object Name) {
            $rel = ('quality-gates/' + $qg.Name)
            $null = Read-JsonFile -RelativePath $rel
            Write-Host "OK:  $rel + $qgSchema"
        }
    }
}

$os = Read-JsonFile -RelativePath 'os-manifest.json'
if ($os) {
    foreach ($prop in $os.manifests.PSObject.Properties) {
        Test-SafeRelativePath -Path ([string]$prop.Value) -Field "os-manifest.manifests.$($prop.Name)"
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ([string]$prop.Value)))) {
            Fail "os-manifest references missing manifest: $($prop.Value)"
        }
    }
    foreach ($prop in $os.entrypoints.PSObject.Properties) {
        Test-SafeRelativePath -Path ([string]$prop.Value) -Field "os-manifest.entrypoints.$($prop.Name)"
        # validateAll/updateProject may be added in this patch; require all declared entrypoints now.
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ([string]$prop.Value)))) {
            Fail "os-manifest references missing entrypoint: $($prop.Value)"
        }
    }
    foreach ($artifact in @($os.managedProjectArtifacts | ForEach-Object { [string]$_ })) {
        Test-SafeRelativePath -Path $artifact -Field 'os-manifest.managedProjectArtifacts'
        $norm = $artifact -replace '\\', '/'
        if ($norm -notmatch '^(\.claude/|AGENTS\.md|\.cursor/rules/|\.agent/|\.agents/)') {
            Fail "managed artifact outside allowed surfaces (.claude/, AGENTS.md, .cursor/rules/, .agent/, .agents/): $artifact"
        }
    }
}

if ($failed) { throw 'JSON contract verification failed.' }

$decisionSchemaPath = Join-Path $RepoRoot 'templates/local/decision-log.schema.json'
if (-not (Test-Path -LiteralPath $decisionSchemaPath)) {
    Fail 'missing templates/local/decision-log.schema.json'
}
else {
    try {
        $ds = Get-Content -LiteralPath $decisionSchemaPath -Raw | ConvertFrom-Json
        if (-not ($ds.PSObject.Properties.Name -contains '$schema')) {
            Fail 'templates/local/decision-log.schema.json missing `$schema'
        }
        if (-not ($ds.PSObject.Properties.Name -contains 'properties')) {
            Fail 'templates/local/decision-log.schema.json missing properties'
        }
        Write-Host 'OK:  templates/local/decision-log.schema.json (decision log contract)'
    }
    catch {
        Fail "invalid JSON: templates/local/decision-log.schema.json — $($_.Exception.Message)"
    }
}

if ($failed) { throw 'JSON contract verification failed.' }

Write-Host ''
Write-Host 'JSON contract checks passed.'
