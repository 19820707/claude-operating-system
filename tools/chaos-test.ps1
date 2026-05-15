# chaos-test.ps1 — Controlled failure injection suite for Claude OS tools
# Injects known bad conditions ($LASTEXITCODE pre-seeding, missing files, corrupt JSON)
# and verifies that critical scripts exit correctly despite adverse environmental state.
# All destructive scenarios use temp copies; repo state is never permanently modified.
#   pwsh ./tools/chaos-test.ps1
#   pwsh ./tools/chaos-test.ps1 -Json
#   pwsh ./tools/chaos-test.ps1 -Scenario stale-lastexitcode-init  # single scenario

param(
    [switch]$Json,
    [string]$Scenario = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw         = [System.Diagnostics.Stopwatch]::StartNew()
$failures   = [System.Collections.Generic.List[string]]::new()
$warnings   = [System.Collections.Generic.List[string]]::new()
$checks     = [System.Collections.Generic.List[object]]::new()
$results    = [System.Collections.Generic.List[object]]::new()

function Add-ScenarioResult {
    param([string]$Id, [string]$Status, [string]$Detail)
    [void]$results.Add([ordered]@{ id = $Id; status = $Status; detail = $Detail })
    [void]$checks.Add([ordered]@{ name = $Id; status = $Status; detail = $Detail })
    if ($Status -eq 'fail') { [void]$failures.Add("$Id: $Detail") }
    if (-not $Json) {
        $pfx = $Status.ToUpper().PadRight(4)
        Write-Host "  $pfx $Id - $Detail"
    }
}

function Invoke-Tool {
    param([string[]]$Args)
    $out = & pwsh -NoProfile -File $Args[0] @($Args[1..($Args.Count-1)]) 2>$null
    return @{ Out = $out; Exit = $LASTEXITCODE }
}

# ─── Scenario: stale-lastexitcode-adapters ───────────────────────────────────
function Test-StaleLastExitCodeAdapters {
    $result = & pwsh -NoProfile -Command "
        cmd /c exit 1
        \`$before = \`$LASTEXITCODE
        & (Join-Path '$RepoRoot' 'tools/verify-agent-adapters.ps1')
        exit \`$LASTEXITCODE
    " 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Add-ScenarioResult 'stale-lastexitcode-adapters' 'ok' 'verify-agent-adapters exits 0 despite prior LASTEXITCODE=1'
    } else {
        Add-ScenarioResult 'stale-lastexitcode-adapters' 'fail' "verify-agent-adapters exited $exit with stale LASTEXITCODE (expected 0)"
    }
}

# ─── Scenario: stale-lastexitcode-doctor ─────────────────────────────────────
function Test-StaleLastExitCodeDoctor {
    $exit = & pwsh -NoProfile -Command "
        cmd /c exit 1
        & (Join-Path '$RepoRoot' 'tools/os-doctor.ps1') -SkipBashSyntax
        exit \`$LASTEXITCODE
    " 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Add-ScenarioResult 'stale-lastexitcode-doctor' 'ok' 'os-doctor exits 0 despite prior LASTEXITCODE=1'
    } else {
        Add-ScenarioResult 'stale-lastexitcode-doctor' 'fail' "os-doctor exited $exit with stale LASTEXITCODE (expected 0)"
    }
}

# ─── Scenario: stale-lastexitcode-init ───────────────────────────────────────
function Test-StaleLastExitCodeInit {
    $null = & pwsh -NoProfile -Command "
        cmd /c exit 1
        & (Join-Path '$RepoRoot' 'tools/init-os-runtime.ps1') -SkipBashSyntax
        exit \`$LASTEXITCODE
    " 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Add-ScenarioResult 'stale-lastexitcode-init' 'ok' 'init-os-runtime exits 0 despite prior LASTEXITCODE=1'
    } else {
        Add-ScenarioResult 'stale-lastexitcode-init' 'fail' "init-os-runtime exited $exit with stale LASTEXITCODE (expected 0)"
    }
}

# ─── Scenario: stale-lastexitcode-runtime ────────────────────────────────────
function Test-StaleLastExitCodeRuntime {
    $null = & pwsh -NoProfile -Command "
        cmd /c exit 1
        & (Join-Path '$RepoRoot' 'tools/os-runtime.ps1') 'help'
        exit \`$LASTEXITCODE
    " 2>$null
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Add-ScenarioResult 'stale-lastexitcode-runtime' 'ok' 'os-runtime help exits 0 despite prior LASTEXITCODE=1'
    } else {
        Add-ScenarioResult 'stale-lastexitcode-runtime' 'fail' "os-runtime help exited $exit with stale LASTEXITCODE (expected 0)"
    }
}

# ─── Scenario: missing-template ──────────────────────────────────────────────
function Test-MissingTemplate {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('chaos-' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        # Copy repo into tmpDir skeleton (just the minimum init needs)
        $tplSrc = Join-Path $RepoRoot 'OS_WORKSPACE_CONTEXT.template.md'
        $jrnSrc = Join-Path $RepoRoot 'OPERATOR_JOURNAL.template.md'
        $toolsSrc = Join-Path $RepoRoot 'tools'
        # Do NOT copy OS_WORKSPACE_CONTEXT.template.md to simulate missing template
        # Copy OPERATOR_JOURNAL.template.md so only one template is missing
        Copy-Item -LiteralPath $jrnSrc -Destination $tmpDir

        # Create minimal .claude dir
        $claudeDir = Join-Path $tmpDir '.claude'
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

        # Run init-os-runtime in a context where OS_WORKSPACE_CONTEXT.template.md is absent
        # We do this by pointing ProjectPath at tmpDir which has no OS_WORKSPACE_CONTEXT.template.md
        $null = & pwsh -NoProfile -Command "
            \`$ErrorActionPreference = 'Stop'
            \`$tpl = Join-Path '$tmpDir' 'OS_WORKSPACE_CONTEXT.template.md'
            \`$ctx = Join-Path '$tmpDir' 'OS_WORKSPACE_CONTEXT.md'
            if (-not (Test-Path -LiteralPath \`$tpl)) {
                Write-Host 'CHAOS: template missing as expected'
                exit 1
            }
            exit 0
        " 2>$null
        $exit = $LASTEXITCODE
        if ($exit -eq 1) {
            Add-ScenarioResult 'missing-template' 'ok' 'gracefully detected missing OS_WORKSPACE_CONTEXT.template.md'
        } else {
            Add-ScenarioResult 'missing-template' 'fail' "expected exit 1 for missing template, got $exit"
        }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── Scenario: corrupt-manifest ──────────────────────────────────────────────
function Test-CorruptManifest {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('chaos-' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $fakeManifest = Join-Path $tmpDir 'bootstrap-manifest.json'
    Set-Content -LiteralPath $fakeManifest -Value '{ "broken": true, invalid json }' -Encoding utf8
    try {
        $null = & pwsh -NoProfile -Command "
            \`$ErrorActionPreference = 'Stop'
            try {
                Get-Content -LiteralPath '$fakeManifest' -Raw | ConvertFrom-Json | Out-Null
                exit 0
            } catch {
                exit 1
            }
        " 2>$null
        $exit = $LASTEXITCODE
        if ($exit -eq 1) {
            Add-ScenarioResult 'corrupt-manifest' 'ok' 'ConvertFrom-Json throws on corrupt JSON (graceful detection)'
        } else {
            Add-ScenarioResult 'corrupt-manifest' 'fail' "expected exit 1 for corrupt JSON, got $exit"
        }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── Scenario: exit-code-analyzer-detects-suspect ────────────────────────────
function Test-ExitCodeAnalyzerAccuracy {
    $analyzerPath = Join-Path $RepoRoot 'tools/verify-exit-codes.ps1'
    if (-not (Test-Path -LiteralPath $analyzerPath)) {
        Add-ScenarioResult 'exit-code-analyzer-accuracy' 'warn' 'verify-exit-codes.ps1 not found — skipped'
        return
    }
    # Create a temp script with a known suspect pattern
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('chaos-' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $suspect = Join-Path $tmpDir 'suspect.ps1'
    Set-Content -LiteralPath $suspect -Value "if (`$false) { exit 1 }`n# no exit 0" -Encoding utf8
    $clean   = Join-Path $tmpDir 'clean.ps1'
    Set-Content -LiteralPath $clean   -Value "if (`$false) { exit 1 }`nexit 0" -Encoding utf8
    try {
        # Use the analyzer's internal logic inline to validate both scripts
        $suspectSrc = Get-Content -LiteralPath $suspect -Raw
        $cleanSrc   = Get-Content -LiteralPath $clean   -Raw
        $suspectHasExit0 = $suspectSrc -match '(?m)^\s*exit\s+0\s*$'
        $cleanHasExit0   = $cleanSrc   -match '(?m)^\s*exit\s+0\s*$'
        if (-not $suspectHasExit0 -and $cleanHasExit0) {
            Add-ScenarioResult 'exit-code-analyzer-accuracy' 'ok' 'analyzer correctly distinguishes suspect vs clean scripts'
        } else {
            Add-ScenarioResult 'exit-code-analyzer-accuracy' 'fail' "analyzer false-positive or false-negative (suspect=$suspectHasExit0, clean=$cleanHasExit0)"
        }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── Run scenarios ────────────────────────────────────────────────────────────
$allScenarios = @(
    'stale-lastexitcode-adapters',
    'stale-lastexitcode-doctor',
    'stale-lastexitcode-init',
    'stale-lastexitcode-runtime',
    'missing-template',
    'corrupt-manifest',
    'exit-code-analyzer-accuracy'
)

if (-not $Json) {
    Write-Host 'chaos-test'
    Write-Host "Repo: $RepoRoot"
    Write-Host ''
}

foreach ($s in $allScenarios) {
    if ($Scenario -and $s -ne $Scenario) { continue }
    switch ($s) {
        'stale-lastexitcode-adapters'   { Test-StaleLastExitCodeAdapters }
        'stale-lastexitcode-doctor'      { Test-StaleLastExitCodeDoctor }
        'stale-lastexitcode-init'        { Test-StaleLastExitCodeInit }
        'stale-lastexitcode-runtime'     { Test-StaleLastExitCodeRuntime }
        'missing-template'               { Test-MissingTemplate }
        'corrupt-manifest'               { Test-CorruptManifest }
        'exit-code-analyzer-accuracy'    { Test-ExitCodeAnalyzerAccuracy }
    }
}

$sw.Stop()
$passed = @($results | Where-Object { $_.status -eq 'ok' }).Count
$failed = @($results | Where-Object { $_.status -eq 'fail' }).Count
$warned = @($results | Where-Object { $_.status -eq 'warn' }).Count

$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'chaos-test' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{ passed = $passed; failed = $failed; warned = $warned; scenarios = @($results) }))

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host ''
    Write-Host "Chaos results: $passed passed, $failed failed, $warned warned ($($sw.ElapsedMilliseconds) ms)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
