# write-validation-history.ps1 — Append one JSONL validation record (opt-in; no secrets)
# Dot-source safe-output before calling Write-ValidationHistoryLine from other scripts, or invoke standalone:
#   $o = @{ ... }; pwsh ./tools/write-validation-history.ps1 -Record ($o | ConvertTo-Json -Compress)
#   pwsh ./tools/write-validation-history.ps1 -Record (...) -DryRun   # no append; prints plan unless -Quiet

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Record,

    [string]$RepoRoot = '',
    [switch]$Quiet,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')

try {
    $obj = $Record | ConvertFrom-Json
}
catch {
    throw 'Record must be valid JSON string.'
}

$logDir = Join-Path $RepoRoot 'logs'
$path = Join-Path $logDir 'validation-history.jsonl'

$simulate = [bool]($DryRun -or -not $PSCmdlet.ShouldProcess($path, 'append validation history line'))
if ($simulate) {
    if (-not $Quiet) {
        Write-Host "[dry-run] would append one JSONL record to $path"
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

if ($obj.PSObject.Properties.Name -contains 'timestamp') {
    $ts = [string]$obj.timestamp
}
else {
    $ts = (Get-Date).ToUniversalTime().ToString('o')
}

$out = [ordered]@{}
foreach ($p in $obj.PSObject.Properties.Name | Sort-Object) {
    $v = $obj.$p
    if ($v -is [string]) {
        $out[$p] = Redact-SensitiveText -Text $v -MaxLength 8000
    }
    else {
        $out[$p] = $v
    }
}
if (-not ($out.ContainsKey('timestamp'))) { $out['timestamp'] = $ts }

$line = ($out | ConvertTo-Json -Depth 12 -Compress)
Add-Content -LiteralPath $path -Value $line -Encoding utf8
if (-not $Quiet) {
    Write-Host "Appended validation history line to $path"
}
