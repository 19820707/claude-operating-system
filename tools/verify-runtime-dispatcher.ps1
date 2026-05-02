# verify-runtime-dispatcher.ps1 — Contract tests for tools/os-runtime.ps1 (read-only)
#   pwsh ./tools/verify-runtime-dispatcher.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$rt = Join-Path $RepoRoot 'tools/os-runtime.ps1'

function Invoke-RT {
    param([string[]]$RtArgs)
    # Drop stderr so host noise does not break JSON parsing.
    $out = & pwsh -NoProfile -File $rt @RtArgs 2>$null
    return @{
        Out   = $out
        Exit  = $LASTEXITCODE
    }
}

$help = Invoke-RT @('help')
if ($help.Exit -ne 0) { throw 'dispatcher: help must exit 0' }
$h = ($help.Out | Out-String)
if (-not $h.Contains('Claude OS Runtime v1')) { throw 'dispatcher: help output must include Runtime v1 (capturable)' }

$wf = Invoke-RT @('workflow', '-Phase', 'verify', '-Json')
if ($wf.Exit -ne 0) { throw 'dispatcher: workflow -Json must exit 0' }
$null = ($wf.Out | Out-String) | ConvertFrom-Json

$route = Invoke-RT @('route', '-Query', 'bootstrap', '-Json')
if ($route.Exit -ne 0) { throw 'dispatcher: route -Json must exit 0' }
$null = ($route.Out | Out-String) | ConvertFrom-Json

$docs = Invoke-RT @('docs', '-Query', 'bootstrap', '-Json')
if ($docs.Exit -ne 0) { throw 'dispatcher: docs -Json must exit 0' }
$null = ($docs.Out | Out-String) | ConvertFrom-Json

$prof = Invoke-RT @('profile', '-Id', 'core', '-Json')
if ($prof.Exit -ne 0) { throw 'dispatcher: profile -Json must exit 0' }
$null = ($prof.Out | Out-String) | ConvertFrom-Json

# Strict forwarding is asserted statically (full validate -Strict runs in os-validate-all / CI only).
$src = Get-Content -LiteralPath $rt -Raw
if (-not $src.Contains('$params[''Strict'']')) {
    throw "dispatcher: os-runtime.ps1 must forward -Strict to os-validate-all (expected splat key Strict)."
}

$abs = Invoke-RT @('absorb')
if ($abs.Exit -eq 0) { throw 'dispatcher: absorb without -Note must fail (non-zero)' }

$dig = Invoke-RT @('digest')
if ($dig.Exit -eq 0) { throw 'dispatcher: digest without -Summary must fail (non-zero)' }

Write-Host 'verify-runtime-dispatcher: OK'
