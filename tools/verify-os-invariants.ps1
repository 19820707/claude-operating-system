# verify-os-invariants.ps1 — Read-only architectural invariants (no mutations)
#   pwsh ./tools/verify-os-invariants.ps1
#   pwsh ./tools/verify-os-invariants.ps1 -Json

param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')

$script:InvFails = [System.Collections.Generic.List[string]]::new()

function Add-InvFail {
    param([string]$Msg)
    [void]$script:InvFails.Add((Redact-SensitiveText -Text $Msg -MaxLength 400))
}

$artifactPattern = '^(\.claude/|AGENTS\.md|\.cursor/rules/|\.agent/|\.agents/)'

$os = Get-Content -LiteralPath (Join-Path $RepoRoot 'os-manifest.json') -Raw | ConvertFrom-Json
foreach ($rel in @($os.managedProjectArtifacts | ForEach-Object { [string]$_ })) {
    $norm = $rel -replace '\\', '/'
    if ($norm -notmatch $artifactPattern) {
        Add-InvFail "os-manifest managedProjectArtifacts path outside adapter/runtime surfaces: $norm"
    }
}

$ad = Get-Content -LiteralPath (Join-Path $RepoRoot 'agent-adapters-manifest.json') -Raw | ConvertFrom-Json
foreach ($a in @($ad.adapters)) {
    $rp = (([string]$a.runtimePath).TrimEnd('/', '\') -replace '\\', '/') + '/'
    if ($rp -ine '.claude/') {
        Add-InvFail "adapter '$($a.id)' runtimePath must be exactly '.claude/' (got '$($a.runtimePath)')"
    }
}

$bm = Get-Content -LiteralPath (Join-Path $RepoRoot 'bootstrap-manifest.json') -Raw | ConvertFrom-Json
$antiPatterns = @('\.cursor-os', '\.codex-os', 'parallel-os', '\.claude-os-copy')
foreach ($rel in @($bm.projectBootstrap.criticalPaths | ForEach-Object { [string]$_ })) {
    $norm = $rel -replace '\\', '/'
    foreach ($ap in $antiPatterns) {
        if ($norm -match $ap) {
            Add-InvFail "bootstrap criticalPaths must not reference forbidden parallel runtime token ($ap): $norm"
        }
    }
}

$adapterDir = Join-Path $RepoRoot 'templates/adapters'
$allowedAdapterFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    'AGENTS.md',
    'cursor-claude-os-runtime.mdc',
    'agent-runtime.md',
    'agent-handoff.md',
    'agent-operating-contract.md',
    'agents-OPERATING_CONTRACT.md'
) | ForEach-Object { [void]$allowedAdapterFiles.Add($_) }

if (Test-Path -LiteralPath $adapterDir) {
    foreach ($f in Get-ChildItem -LiteralPath $adapterDir -File) {
        if (-not $allowedAdapterFiles.Contains($f.Name)) {
            Add-InvFail "templates/adapters contains unexpected file (whitelist): $($f.Name)"
        }
    }
} else {
    Add-InvFail 'templates/adapters directory missing'
}

$status = if ($script:InvFails.Count -gt 0) { 'fail' } else { 'ok' }
$out = [ordered]@{
    name     = 'verify-os-invariants'
    status   = $status
    failures = $script:InvFails.Count
    messages = @($script:InvFails)
    repoRoot = (Redact-SensitiveText -Text $RepoRoot -MaxLength 200)
}

if ($Json) {
    $out | ConvertTo-Json -Depth 6 -Compress | Write-Output
} else {
    Write-Host 'verify-os-invariants'
    Write-Host "Repo: $RepoRoot"
    foreach ($m in $script:InvFails) { Write-Host "  FAIL $m" }
    if ($script:InvFails.Count -eq 0) { Write-Host 'OK:  OS architectural invariants' }
}

if ($script:InvFails.Count -gt 0) {
    throw "OS invariant verification failed: $($script:InvFails.Count) issue(s)."
}
exit 0
