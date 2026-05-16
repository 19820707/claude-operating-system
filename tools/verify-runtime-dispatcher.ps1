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

$init = Invoke-RT @('init', '-SkipBashSyntax')
if ($init.Exit -ne 0) { throw 'dispatcher: init -SkipBashSyntax must exit 0' }

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

# Strict / bash flags must be forwarded via splat (never reuse $args as a local variable).
# Do not invoke `validate` from this script: os-validate-all -> health -> verify-runtime-dispatcher would recurse.
$src = Get-Content -LiteralPath $rt -Raw
if ($src -notmatch "'init'") {
    throw "dispatcher: os-runtime.ps1 must include init command in ValidateSet."
}
if (-not $src.Contains('init-os-runtime.ps1')) {
    throw 'dispatcher: os-runtime.ps1 must invoke tools/init-os-runtime.ps1 for init.'
}
if (-not $src.Contains('os-validate.ps1')) {
    throw 'dispatcher: os-runtime.ps1 must invoke tools/os-validate.ps1 for profiled validate.'
}
if (-not $src.Contains('$params[''Strict'']')) {
    throw "dispatcher: os-runtime.ps1 must forward -Strict to os-validate-all (expected splat key Strict)."
}
if (-not $src.Contains('$params[''SkipBashSyntax'']')) {
    throw "dispatcher: os-runtime.ps1 must forward -SkipBashSyntax to os-validate-all when set."
}

$abs = Invoke-RT @('absorb')
if ($abs.Exit -eq 0) { throw 'dispatcher: absorb without -Note must fail (non-zero)' }

$dig = Invoke-RT @('digest')
if ($dig.Exit -eq 0) { throw 'dispatcher: digest without -Summary must fail (non-zero)' }

Write-Host 'verify-runtime-dispatcher: OK'
exit 0
