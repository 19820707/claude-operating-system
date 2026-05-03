# verify-examples.ps1 — Validate examples/*.json against Claude OS JSON Schemas (subset validator, no Node)
#   pwsh ./tools/verify-examples.ps1
# Subset supports: type, required, properties, items, enum, minimum/maximum, min/maxLength,
# pattern, min/maxItems, uniqueItems, additionalProperties, $ref to #/$defs/* in the same schema file.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Get-SchemaDefsRoot {
    param([object]$SchemaRoot)
    $prop = $SchemaRoot.PSObject.Properties | Where-Object { $_.Name -eq '$defs' }
    if ($prop) { return $prop.Value }
    return $null
}

function Resolve-SchemaNode {
    param(
        [object]$SchemaRoot,
        [object]$Node
    )
    if ($null -eq $Node) { return $null }
    if ($Node -is [string] -or $Node -is [bool] -or $Node -is [int] -or $Node -is [long] -or $Node -is [double]) {
        return $Node
    }
    $refProp = $Node.PSObject.Properties['$ref']
    if ($refProp -and @($Node.PSObject.Properties).Count -eq 1) {
        $r = [string]$refProp.Value
        if ($r -notmatch '^#/\$defs/(.+)$') {
            throw "unsupported `$ref (only #/\`$defs/...): $r"
        }
        $seg = $Matches[1]
        $defs = Get-SchemaDefsRoot -SchemaRoot $SchemaRoot
        if (-not $defs) { throw 'schema missing `$defs for $ref' }
        $sub = $defs.PSObject.Properties[$seg]
        if (-not $sub) { throw "`$defs segment not found: $seg" }
        return (Resolve-SchemaNode -SchemaRoot $SchemaRoot -Node $sub.Value)
    }
    return $Node
}

function Test-IsWholeNumber {
    param($n)
    if ($n -is [int] -or $n -is [long] -or $n -is [byte] -or $n -is [short]) { return $true }
    if ($n -is [double] -or $n -is [decimal]) {
        return [math]::Abs([double]$n - [math]::Round([double]$n, 0)) -lt 1e-9
    }
    return $false
}

function Test-OsSchemaInstance {
    param(
        [object]$Instance,
        [object]$SchemaNode,
        [object]$SchemaRoot,
        [string]$Path = '$'
    )
    $schema = Resolve-SchemaNode -SchemaRoot $SchemaRoot -Node $SchemaNode
    if ($null -eq $schema) { return }

    if ($schema.PSObject.Properties['enum']) {
        $allowed = @($schema.enum | ForEach-Object { $_ })
        if ($Instance -notin $allowed) {
            throw "enum mismatch at $Path : value '$Instance' not in $($allowed -join ',')"
        }
        return
    }

    $type = $null
    $tp = $schema.PSObject.Properties['type']
    if ($tp) { $type = [string]$tp.Value }

    if ($type -eq 'object') {
        if ($null -eq $Instance) { throw "expected object at $Path, got null" }
        if ($Instance -isnot [System.Collections.IDictionary] -and $Instance.PSObject -eq $null) {
            throw "expected object at $Path, got $($Instance.GetType().FullName)"
        }
        $req = @()
        $rp = $schema.PSObject.Properties['required']
        if ($rp) { $req = @($rp.Value | ForEach-Object { [string]$_ }) }
        foreach ($k in $req) {
            $has = if ($Instance -is [System.Collections.IDictionary]) { $Instance.ContainsKey($k) } else { $null -ne ($Instance.PSObject.Properties[$k]) }
            if (-not $has) { throw "missing required property '$k' at $Path" }
        }
        $props = $null
        $pp = $schema.PSObject.Properties['properties']
        if ($pp) { $props = $pp.Value }
        $add = $true
        $ap = $schema.PSObject.Properties['additionalProperties']
        if ($null -ne $ap) { $add = [bool]$ap.Value }

        $names = if ($Instance -is [System.Collections.IDictionary]) {
            @($Instance.Keys | ForEach-Object { [string]$_ })
        }
        else {
            @($Instance.PSObject.Properties | ForEach-Object { $_.Name })
        }
        foreach ($name in $names) {
            $child = if ($Instance -is [System.Collections.IDictionary]) { $Instance[$name] } else { $Instance.PSObject.Properties[$name].Value }
            $subSchema = $null
            if ($props) {
                $pdef = $props.PSObject.Properties[$name]
                if ($pdef) { $subSchema = $pdef.Value }
            }
            if ($null -eq $subSchema) {
                if (-not $add) { throw "additional property disallowed at ${Path}.$name" }
                continue
            }
            Test-OsSchemaInstance -Instance $child -SchemaNode $subSchema -SchemaRoot $SchemaRoot -Path "$Path.$name"
        }
        return
    }

    if ($type -eq 'array') {
        # ConvertFrom-Json maps JSON [] to $null; treat as empty array.
        $arr = if ($null -eq $Instance) { @() } else { @($Instance) }
        $minI = $schema.PSObject.Properties['minItems']
        if ($minI -and $arr.Count -lt [int]$minI.Value) { throw "minItems at $Path : $($arr.Count) < $($minI.Value)" }
        $maxI = $schema.PSObject.Properties['maxItems']
        if ($maxI -and $arr.Count -gt [int]$maxI.Value) { throw "maxItems at $Path : $($arr.Count) > $($maxI.Value)" }
        $uniq = $schema.PSObject.Properties['uniqueItems']
        if ($uniq -and [bool]$uniq.Value) {
            $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($el in $arr) {
                $key = if ($null -eq $el) { 'null:' }
                elseif ($el -is [string]) { "s:$el" }
                elseif ($el -is [bool]) { "b:$el" }
                elseif (Test-IsWholeNumber $el) { "n:$el" }
                else { ($el | ConvertTo-Json -Compress -Depth 25) }
                if (-not $seen.Add($key)) { throw "uniqueItems violated at $Path" }
            }
        }
        $items = $schema.PSObject.Properties['items']
        if ($items) {
            $ix = 0
            foreach ($el in $arr) {
                Test-OsSchemaInstance -Instance $el -SchemaNode $items.Value -SchemaRoot $SchemaRoot -Path "$Path[$ix]"
                $ix++
            }
        }
        return
    }

    if ($type -eq 'string') {
        # ConvertFrom-Json may deserialize ISO-8601-looking values as [datetime].
        if ($Instance -is [datetime]) {
            $Instance = $Instance.ToUniversalTime().ToString('o')
        }
        if ($Instance -isnot [string]) { throw "expected string at $Path" }
        $minL = $schema.PSObject.Properties['minLength']
        if ($minL -and $Instance.Length -lt [int]$minL.Value) { throw "minLength at $Path" }
        $maxL = $schema.PSObject.Properties['maxLength']
        if ($maxL -and $Instance.Length -gt [int]$maxL.Value) { throw "maxLength at $Path" }
        $pat = $schema.PSObject.Properties['pattern']
        if ($pat) {
            $rx = [string]$pat.Value
            if ($Instance -notmatch $rx) { throw "pattern mismatch at $Path (pattern $rx)" }
        }
        return
    }

    if ($type -eq 'integer') {
        if (-not (Test-IsWholeNumber $Instance)) { throw "expected integer at $Path" }
        $mn = $schema.PSObject.Properties['minimum']
        if ($mn -and [decimal]$Instance -lt [decimal]$mn.Value) { throw "minimum at $Path" }
        $mx = $schema.PSObject.Properties['maximum']
        if ($mx -and [decimal]$Instance -gt [decimal]$mx.Value) { throw "maximum at $Path" }
        return
    }

    if ($type -eq 'number') {
        if ($null -eq $Instance -or (($Instance -isnot [double] -and $Instance -isnot [decimal] -and $Instance -isnot [int] -and $Instance -isnot [long]))) {
            if ($Instance -is [string]) { throw "expected number at $Path" }
        }
        $mn = $schema.PSObject.Properties['minimum']
        if ($mn -and [decimal]$Instance -lt [decimal]$mn.Value) { throw "minimum at $Path" }
        $mx = $schema.PSObject.Properties['maximum']
        if ($mx -and [decimal]$Instance -gt [decimal]$mx.Value) { throw "maximum at $Path" }
        return
    }

    if ($type -eq 'boolean') {
        if ($Instance -isnot [bool]) { throw "expected boolean at $Path" }
        return
    }

    if ([string]::IsNullOrWhiteSpace($type)) {
        return
    }
    throw "unsupported schema type '$type' at schema path (instance $Path)"
}

function Read-JsonObject {
    param([string]$AbsolutePath)
    $raw = Get-Content -LiteralPath $AbsolutePath -Raw -Encoding utf8
    return ($raw | ConvertFrom-Json)
}

$examplePairs = @(
    @{ relExample = 'examples/validation/os-validate-quick-ok.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/os-validate-standard-warn.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/os-validate-strict-fail.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/verify-agent-adapter-drift-warn.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/verify-skills-manifest-fail.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/verify-doc-contract-fail.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/verify-runtime-budget-warn.json'; relSchema = 'schemas/os-validator-envelope.schema.json' }
    @{ relExample = 'examples/validation/verify-os-health-ok.json'; relSchema = 'schemas/os-health-envelope.schema.json' }
    @{ relExample = 'examples/validation/runtime-budget-minimal-example.json'; relSchema = 'schemas/runtime-budget.schema.json' }
    @{ relExample = 'examples/skills/skills-manifest-minimal-example.json'; relSchema = 'schemas/skills-manifest.schema.json' }
    @{ relExample = 'examples/playbooks/playbook-manifest-minimal-example.json'; relSchema = 'schemas/playbook-manifest.schema.json' }
    @{ relExample = 'examples/project-bootstrap/bootstrap-manifest-minimal-example.json'; relSchema = 'schemas/bootstrap-manifest.schema.json' }
    @{ relExample = 'examples/audit/audit-evidence-manifest-minimal-example.json'; relSchema = 'schemas/audit-evidence-manifest.schema.json' }
)

Write-Host 'verify-examples'
$failed = $false
foreach ($row in $examplePairs) {
    $ex = Join-Path $RepoRoot $row.relExample
    $sc = Join-Path $RepoRoot $row.relSchema
    if (-not (Test-Path -LiteralPath $ex)) {
        Write-Host "FAIL: missing $($row.relExample)"
        $failed = $true
        continue
    }
    if (-not (Test-Path -LiteralPath $sc)) {
        Write-Host "FAIL: missing $($row.relSchema)"
        $failed = $true
        continue
    }
    try {
        $inst = Read-JsonObject -AbsolutePath $ex
        $schema = Read-JsonObject -AbsolutePath $sc
        Test-OsSchemaInstance -Instance $inst -SchemaNode $schema -SchemaRoot $schema -Path '$'
        Write-Host "OK:  $($row.relExample) <= $($row.relSchema)"
    }
    catch {
        Write-Host "FAIL: $($row.relExample) — $($_.Exception.Message)"
        $failed = $true
    }
}

if ($failed) { throw 'Example JSON schema validation failed.' }
Write-Host ''
Write-Host 'All example documents validated against their schemas.'
exit 0
