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

function Require-SchemaVersion {
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
    'docs-index.json' = 'schemas/docs-index.schema.json'
    'os-capabilities.json' = 'schemas/os-capabilities.schema.json'
    'workflow-manifest.json' = 'schemas/workflow-manifest.schema.json'
    'agent-adapters-manifest.json' = 'schemas/agent-adapters-manifest.schema.json'
}

foreach ($pair in $manifestPairs.GetEnumerator() | Sort-Object Name) {
    $json = Read-JsonFile -RelativePath $pair.Key
    $schema = Read-JsonFile -RelativePath $pair.Value
    Require-SchemaVersion -Json $json -Name $pair.Key
    if (-not $schema) { continue }
    if (-not ($schema.PSObject.Properties.Name -contains '$schema')) { Fail "$($pair.Value) missing `$schema declaration" }
    Write-Host "OK:  $($pair.Key) + $($pair.Value)"
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
        if (-not $artifact.StartsWith('.claude/')) { Fail "managed artifact must be under .claude/: $artifact" }
    }
}

if ($failed) { throw 'JSON contract verification failed.' }

Write-Host ''
Write-Host 'JSON contract checks passed.'
