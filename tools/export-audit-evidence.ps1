# export-audit-evidence.ps1 — Sanitized audit evidence bundle + manifest (no env values, no secrets, no .env contents)
#   pwsh ./tools/export-audit-evidence.ps1 -OutputPath ./exports/audit-run-1
#   pwsh ./tools/export-audit-evidence.ps1 -OutputPath ./exports/audit-run-1 -Json
#   pwsh ./tools/export-audit-evidence.ps1 -OutputPath ./exports/audit-run-1 -DryRun [-Json]
#   pwsh ./tools/export-audit-evidence.ps1 -OutputPath ./exports/audit-run-1 -IncludeStrictValidation [-SkipBashSyntax]

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$Json,

    [switch]$IncludeStrictValidation,

    [switch]$SkipBashSyntax,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')

function Get-RepoRootTail {
    param([string]$Full)
    $norm = $Full.TrimEnd('\', '/') -replace '\\', '/'
    $parts = $norm -split '/' | Where-Object { $_ }
    if ($parts.Count -le 2) { return $norm }
    return ($parts[-2] + '/' + $parts[-1])
}

function Invoke-PwshJsonLine {
    param(
        [string]$RelativeTool,
        [string[]]$ArgList
    )
    $p = Join-Path $RepoRoot $RelativeTool
    $all = @('-NoProfile', '-File', $p) + $ArgList
    $out = @(& pwsh @all 2>$null)
    $code = $LASTEXITCODE
    $line = $out | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
    $obj = $null
    if ($line) {
        try { $obj = $line | ConvertFrom-Json } catch { $obj = $null }
    }
    return @{ exitCode = [int]$code; object = $obj; stderrSuppressed = $true }
}

function Get-Sha256HexUtf8NoBom {
    param([string]$Text)
    $enc = [System.Text.UTF8Encoding]::new($false)
    $bytes = $enc.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Get-CommandVersionLine {
    param([string]$Name, [string[]]$ArgList)
    try {
        $cmd = Get-Command $Name -ErrorAction SilentlyContinue
        if (-not $cmd) { return $null }
        $one = & $Name @ArgList 2>$null | Select-Object -First 1
        if (-not $one) { return $null }
        return (Redact-SensitiveText -Text ([string]$one) -MaxLength 200)
    }
    catch {
        return $null
    }
}

$outDir = $OutputPath
if (-not [System.IO.Path]::IsPathRooted($outDir)) {
    $outDir = Join-Path $RepoRoot $outDir
}
$outDir = [System.IO.Path]::GetFullPath($outDir)
if (-not (Test-Path -LiteralPath $outDir) -and -not $DryRun) {
    $null = New-Item -ItemType Directory -Path $outDir -Force
}

$bundle = [ordered]@{
    schemaVersion        = 1
    generatedAt          = (Get-Date).ToUniversalTime().ToString('o')
    repoRootTail         = (Get-RepoRootTail -Full $RepoRoot)
    options              = [ordered]@{
        includeStrictValidation = [bool]$IncludeStrictValidation
        skipBashSyntax            = [bool]$SkipBashSyntax
    }
    osManifestSummary    = $null
    runtimeProfilesSummary = $null
    validationQuick      = $null
    validationStrict     = $null
    skillsManifestSummary = $null
    adapterDrift         = $null
    gitHygiene           = $null
    powershellRuntime    = $null
    bashAvailability     = $null
    osSummary            = $null
    workspaceContextMeta = $null
    dotenvPresence       = $null
    commandVersions      = [ordered]@{}
}

# --- os-manifest summary (no secrets; relative paths only) ---
try {
    $omPath = Join-Path $RepoRoot 'os-manifest.json'
    $om = Get-Content -LiteralPath $omPath -Raw -Encoding utf8 | ConvertFrom-Json
    $manifestKeys = @()
    if ($null -ne $om.manifests) {
        $manifestKeys = @($om.manifests.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    }
    $entryKeys = @()
    if ($null -ne $om.entrypoints) {
        $entryKeys = @($om.entrypoints.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    }
    $bundle.osManifestSummary = [ordered]@{
        schemaVersion = [int]$om.schemaVersion
        runtimeName   = (Redact-SensitiveText -Text ([string]$om.runtime.name) -MaxLength 120)
        runtimeVersion = (Redact-SensitiveText -Text ([string]$om.runtime.version) -MaxLength 40)
        descriptionSnippet = (Redact-SensitiveText -Text ([string]$om.description) -MaxLength 280)
        manifestKeys  = $manifestKeys
        entrypointKeys = $entryKeys
        managedArtifactCount = @($om.managedProjectArtifacts | ForEach-Object { $_ }).Count
    }
}
catch {
    $bundle.osManifestSummary = [ordered]@{ error = (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400) }
}

# --- runtime profiles ---
try {
    $rpPath = Join-Path $RepoRoot 'runtime-profiles.json'
    $rp = Get-Content -LiteralPath $rpPath -Raw -Encoding utf8 | ConvertFrom-Json
    $profiles = foreach ($prof in @($rp.profiles)) {
        $cmds = @($prof.commands | ForEach-Object { [string]$_ })
        [ordered]@{
            id            = [string]$prof.id
            commandCount  = $cmds.Count
            purposeSnippet = (Redact-SensitiveText -Text ([string]$prof.purpose) -MaxLength 220)
            default       = [bool]$prof.default
        }
    }
    $bundle.runtimeProfilesSummary = [ordered]@{
        schemaVersion = [int]$rp.schemaVersion
        profileCount  = @($profiles).Count
        profiles      = @($profiles)
    }
}
catch {
    $bundle.runtimeProfilesSummary = [ordered]@{ error = (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400) }
}

# --- validation quick ---
$vqArgs = @('-Profile', 'quick', '-Json')
if ($SkipBashSyntax) { $vqArgs += '-SkipBashSyntax' }
$vq = Invoke-PwshJsonLine -RelativeTool 'tools/os-validate.ps1' -ArgList $vqArgs
$bundle.validationQuick = [ordered]@{
    exitCode = $vq.exitCode
    envelope = $vq.object
}

# --- validation strict (optional) ---
if ($IncludeStrictValidation) {
    $vsArgs = @('-Profile', 'strict', '-Json')
    if ($SkipBashSyntax) { $vsArgs += '-SkipBashSyntax' }
    $vs = Invoke-PwshJsonLine -RelativeTool 'tools/os-validate.ps1' -ArgList $vsArgs
    $bundle.validationStrict = [ordered]@{
        exitCode = $vs.exitCode
        envelope = $vs.object
    }
}
else {
    $bundle.validationStrict = [ordered]@{ skipped = $true; reason = '-IncludeStrictValidation not set' }
}

# --- skills manifest summary ---
try {
    $smPath = Join-Path $RepoRoot 'skills-manifest.json'
    $sm = Get-Content -LiteralPath $smPath -Raw -Encoding utf8 | ConvertFrom-Json
    $ids = @($sm.skills | ForEach-Object { [string]$_.id })
    $maturity = @{}
    foreach ($sk in @($sm.skills)) {
        $m = [string]$sk.maturity
        if (-not $maturity.ContainsKey($m)) { $maturity[$m] = 0 }
        $maturity[$m]++
    }
    $bundle.skillsManifestSummary = [ordered]@{
        schemaVersion   = [int]$sm.schemaVersion
        canonicalRoot   = (Redact-SensitiveText -Text ([string]$sm.canonicalRoot) -MaxLength 120)
        skillCount      = $ids.Count
        skillIds        = $ids
        maturityHistogram = $maturity
    }
}
catch {
    $bundle.skillsManifestSummary = [ordered]@{ error = (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400) }
}

# --- adapter drift ---
$adArgs = @('-Json')
$ad = Invoke-PwshJsonLine -RelativeTool 'tools/verify-agent-adapter-drift.ps1' -ArgList $adArgs
$bundle.adapterDrift = [ordered]@{
    exitCode = $ad.exitCode
    envelope = $ad.object
}

# --- git hygiene ---
$ghArgs = @('-Json', '-WarnIfNoGit')
$gh = Invoke-PwshJsonLine -RelativeTool 'tools/verify-git-hygiene.ps1' -ArgList $ghArgs
$bundle.gitHygiene = [ordered]@{
    exitCode = $gh.exitCode
    envelope = $gh.object
}

# --- PowerShell runtime (no env dump) ---
$clr = ''
if ($null -ne $PSVersionTable.CLRVersion) { $clr = [string]$PSVersionTable.CLRVersion }
$bundle.powershellRuntime = [ordered]@{
    psVersion            = $PSVersionTable.PSVersion.ToString()
    edition              = [string]$PSVersionTable.PSEdition
    clrVersion           = $clr
    platform             = [string]$PSVersionTable.Platform
    osDescriptionSnippet = (Redact-SensitiveText -Text ([System.Runtime.InteropServices.RuntimeInformation]::OSDescription) -MaxLength 200)
}

# --- Bash availability ---
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
$bundle.bashAvailability = [ordered]@{
    onPath = [bool]$bashCmd
    name   = if ($bashCmd) { [string]$bashCmd.Name } else { '' }
}

# --- OS summary (no machine name) ---
$bundle.osSummary = [ordered]@{
    osVersionString = (Redact-SensitiveText -Text ([System.Environment]::OSVersion.VersionString) -MaxLength 120)
    is64BitProcess  = [System.Environment]::Is64BitOperatingSystem
    processorCount  = [int][System.Environment]::ProcessorCount
    tickCount64     = [System.Environment]::TickCount64
}

# --- OS_WORKSPACE_CONTEXT.md metadata only ---
$ctxPath = Join-Path $RepoRoot 'OS_WORKSPACE_CONTEXT.md'
if (Test-Path -LiteralPath $ctxPath) {
    $item = Get-Item -LiteralPath $ctxPath
    $lines = (Get-Content -LiteralPath $ctxPath -Encoding utf8 | Measure-Object -Line).Lines
    $bundle.workspaceContextMeta = [ordered]@{
        present    = $true
        lineCount  = [int]$lines
        byteLength = [int]$item.Length
        note       = 'Full file contents intentionally omitted from audit bundle.'
    }
}
else {
    $bundle.workspaceContextMeta = [ordered]@{ present = $false }
}

# --- .env presence only (never read file) ---
$envPath = Join-Path $RepoRoot '.env'
$bundle.dotenvPresence = [ordered]@{
    present          = (Test-Path -LiteralPath $envPath)
    contentsIncluded = $false
    note             = '.env contents are never collected.'
}

# --- command versions (sanitized single lines) ---
$cv = [ordered]@{}
$g = Get-CommandVersionLine -Name 'git' -ArgList @('--version')
if ($g) { $cv['git'] = $g }
$pw = Get-CommandVersionLine -Name 'pwsh' -ArgList @('--version')
if ($pw) { $cv['pwsh'] = $pw }
if ($bashCmd) {
    $bv = Get-CommandVersionLine -Name 'bash' -ArgList @('--version')
    if ($bv) { $cv['bash'] = $bv }
}
$bundle.commandVersions = $cv

$bundleJson = $bundle | ConvertTo-Json -Depth 25 -Compress
$bundleHash = Get-Sha256HexUtf8NoBom -Text $bundleJson
$bundleBytes = [System.Text.UTF8Encoding]::new($false).GetByteCount($bundleJson)
$bundleFile = Join-Path $outDir 'evidence-bundle.json'
if (-not $DryRun) {
    [System.IO.File]::WriteAllText($bundleFile, $bundleJson, [System.Text.UTF8Encoding]::new($false))
}

function Test-SectionOk {
    param($part)
    if ($null -eq $part) { return $false }
    if ($part.error) { return $false }
    return $true
}

$sections = [System.Collections.Generic.List[object]]::new()
function Add-Section {
    param([string]$Id, [bool]$Collected, [string]$Pointer, [int]$ExitCode = -1, [string]$Err = '')
    $o = [ordered]@{
        id               = $Id
        collected        = $Collected
        artifactPointer  = $Pointer
    }
    if ($ExitCode -ge 0) { $o['exitCode'] = $ExitCode }
    if ($Err) { $o['error'] = (Redact-SensitiveText -Text $Err -MaxLength 800) }
    [void]$sections.Add($o)
}

Add-Section -Id 'os-manifest' -Collected (Test-SectionOk $bundle.osManifestSummary) -Pointer '/osManifestSummary'
Add-Section -Id 'runtime-profiles' -Collected (Test-SectionOk $bundle.runtimeProfilesSummary) -Pointer '/runtimeProfilesSummary'
Add-Section -Id 'validation-quick' -Collected ($null -ne $bundle.validationQuick.envelope) -Pointer '/validationQuick' -ExitCode $bundle.validationQuick.exitCode
if ($IncludeStrictValidation) {
    Add-Section -Id 'validation-strict' -Collected ($null -ne $bundle.validationStrict.envelope) -Pointer '/validationStrict' -ExitCode $bundle.validationStrict.exitCode
}
else {
    Add-Section -Id 'validation-strict' -Collected $false -Pointer '/validationStrict'
}
Add-Section -Id 'skills-manifest' -Collected (Test-SectionOk $bundle.skillsManifestSummary) -Pointer '/skillsManifestSummary'
Add-Section -Id 'adapter-drift' -Collected ($null -ne $bundle.adapterDrift.envelope) -Pointer '/adapterDrift' -ExitCode $bundle.adapterDrift.exitCode
Add-Section -Id 'git-hygiene' -Collected ($null -ne $bundle.gitHygiene.envelope) -Pointer '/gitHygiene' -ExitCode $bundle.gitHygiene.exitCode
Add-Section -Id 'powershell-runtime' -Collected ($null -ne $bundle.powershellRuntime) -Pointer '/powershellRuntime'
Add-Section -Id 'bash-availability' -Collected ($null -ne $bundle.bashAvailability) -Pointer '/bashAvailability'
Add-Section -Id 'os-summary' -Collected ($null -ne $bundle.osSummary) -Pointer '/osSummary'
Add-Section -Id 'workspace-context-metadata' -Collected ($null -ne $bundle.workspaceContextMeta) -Pointer '/workspaceContextMeta'
Add-Section -Id 'dotenv-presence' -Collected ($null -ne $bundle.dotenvPresence) -Pointer '/dotenvPresence'

$pwLeaf = ''
try {
    $pwc = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwc -and $pwc.Source) { $pwLeaf = [string](Split-Path -Path $pwc.Source -Leaf) }
}
catch { }

$collector = [ordered]@{
    script              = 'tools/export-audit-evidence.ps1'
    powershellVersion   = $bundle.powershellRuntime.psVersion
    powershellEdition   = $bundle.powershellRuntime.edition
}
if ($pwLeaf) { $collector['pwshPathLeaf'] = $pwLeaf }

$manifest = [ordered]@{
    schemaVersion   = 1
    generatedAt     = $bundle.generatedAt
    repoRootTail    = $bundle.repoRootTail
    collector       = $collector
    privacy         = [ordered]@{
        environmentVariableValuesIncluded  = $false
        dotEnvContentsIncluded             = $false
        osWorkspaceContextFullTextIncluded = $false
        secretsEmitted                     = $false
        redactionNotes                     = 'Strings passed through Redact-SensitiveText; no environment variable values; no .env read; OS_WORKSPACE_CONTEXT.md content omitted.'
    }
    options         = $bundle.options
    commandVersions = $bundle.commandVersions
    sections        = @($sections)
    artifacts       = @(
        [ordered]@{
            name       = 'evidence-bundle.json'
            sha256     = $bundleHash
            byteLength = $bundleBytes
        }
    )
}

$manifestJson = $manifest | ConvertTo-Json -Depth 20 -Compress
$manifestFile = Join-Path $outDir 'audit-evidence-manifest.json'
if (-not $DryRun) {
    [System.IO.File]::WriteAllText($manifestFile, $manifestJson, [System.Text.UTF8Encoding]::new($false))
}

if ($Json) {
    if ($DryRun) {
        (@{
                dryRun        = $true
                plannedWrites = @($bundleFile, $manifestFile)
                outDir        = $outDir
            } | ConvertTo-Json -Depth 6 -Compress) | Write-Output
    }
    else {
        $manifestJson | Write-Output
    }
}
else {
    if ($DryRun) {
        Write-Host 'export-audit-evidence: [dry-run] would write'
        Write-Host "  $manifestFile"
        Write-Host "  $bundleFile"
    }
    else {
        Write-Host "export-audit-evidence: wrote"
        Write-Host "  $manifestFile"
        Write-Host "  $bundleFile"
    }
}

exit 0
