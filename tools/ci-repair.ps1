# ci-repair.ps1 — Pattern-driven CI repair advisor (read-only by default)
# Reads a validate-quick.json artifact and/or a text failure log, maps known failure
# patterns to structured repair suggestions. With -Apply, executes safe reversible fixes.
#   pwsh ./tools/ci-repair.ps1
#   pwsh ./tools/ci-repair.ps1 -Json
#   pwsh ./tools/ci-repair.ps1 -Apply          # executes safe auto-repairs
#   pwsh ./tools/ci-repair.ps1 -QuickJson path  # explicit artifact path

param(
    [switch]$Json,
    [switch]$Apply,
    [string]$QuickJson = '',
    [string]$FailLog   = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$failures  = [System.Collections.Generic.List[string]]::new()
$warnings  = [System.Collections.Generic.List[string]]::new()
$checks    = [System.Collections.Generic.List[object]]::new()
$repairs   = [System.Collections.Generic.List[object]]::new()
$applied   = [System.Collections.Generic.List[string]]::new()

# ── Load artifact ─────────────────────────────────────────────────────────────
$quickPath = if ($QuickJson) { $QuickJson } else { Join-Path $RepoRoot 'validate-quick.json' }
$quickData = $null
if (Test-Path -LiteralPath $quickPath) {
    try {
        $quickData = (Get-Content -LiteralPath $quickPath -Raw -Encoding utf8) | ConvertFrom-Json
        [void]$checks.Add([ordered]@{ name = 'read-quick-json'; status = 'ok'; detail = $quickPath })
    } catch {
        [void]$warnings.Add("Could not parse $quickPath: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'read-quick-json'; status = 'warn'; detail = 'parse error' })
    }
} else {
    [void]$warnings.Add("validate-quick.json not found at $quickPath — run os-validate.ps1 -Profile quick -Json first")
    [void]$checks.Add([ordered]@{ name = 'read-quick-json'; status = 'warn'; detail = 'not found' })
}

# Combine failure signals: quick artifact + optional raw log text
$failedNames = @()
if ($null -ne $quickData) {
    $failedNames = @($quickData.failures)
}
if ($FailLog -and (Test-Path -LiteralPath $FailLog)) {
    $logText = Get-Content -LiteralPath $FailLog -Raw
} else {
    $logText = ''
}

# ── Pattern → Repair catalogue ─────────────────────────────────────────────────
function Add-Repair {
    param(
        [string]$Id,
        [string]$Pattern,
        [string]$Cause,
        [string]$Action,
        [scriptblock]$ApplyBlock = $null,
        [bool]$Safe = $false
    )
    [void]$repairs.Add([ordered]@{
        id         = $Id
        pattern    = $Pattern
        cause      = $Cause
        action     = $Action
        safe       = $Safe
        applicable = $false
        applied    = $false
        applyBlock = $ApplyBlock
    })
}

Add-Repair -Id 'dirty-workspace' `
    -Pattern 'dirty=True|Working tree not clean' `
    -Cause 'CI checkout has untracked or modified files. Common cause: validate-quick.json written to workspace root during Profile quick step, not gitignored.' `
    -Action 'Add offending paths to .gitignore. Run: git status --porcelain in CI to identify files.' `
    -Safe $false

Add-Repair -Id 'exit-code-hygiene' `
    -Pattern 'exit-code-hygiene|missing explicit exit 0' `
    -Cause 'A tools/*.ps1 script has a failure path (exit 1/throw) but no explicit exit 0 on the success path. $null -ne 0 is True in PowerShell; stale $LASTEXITCODE propagates across & invocations.' `
    -Action 'Run: pwsh ./tools/verify-exit-codes.ps1 to identify suspects. Add exit 0 at end of each flagged script after the failure-check block.' `
    -Safe $false

Add-Repair -Id 'bootstrap-manifest-count' `
    -Pattern 'verify-bootstrap-manifest|exact count|script count mismatch' `
    -Cause 'bootstrap-manifest.json exact counts are stale after adding or removing files from templates/.' `
    -Action 'Run: pwsh ./tools/verify-bootstrap-manifest.ps1 to see mismatches, then update exact counts in bootstrap-manifest.json.' `
    -ApplyBlock {
        # Safe: recount templates/scripts/*.sh and update bootstrap-manifest.json
        $bm = Join-Path $RepoRoot 'bootstrap-manifest.json'
        $doc = (Get-Content -LiteralPath $bm -Raw) | ConvertFrom-Json
        $actual = @(Get-ChildItem (Join-Path $RepoRoot 'templates/scripts') -Filter '*.sh').Count
        $expected = [int]$doc.repoIntegrity.'templates/scripts'.exact
        if ($actual -ne $expected) {
            $raw = Get-Content -LiteralPath $bm -Raw
            $updated = $raw -replace """exact"": $expected", """exact"": $actual"
            Set-Content -LiteralPath $bm -Value $updated -Encoding utf8
            return "Updated templates/scripts exact count: $expected -> $actual"
        }
        return "Count already correct ($actual)"
    } `
    -Safe $true

Add-Repair -Id 'script-manifest-missing' `
    -Pattern 'not listed in script-manifest|shellScripts.*missing|verify-script-manifest' `
    -Cause 'A new shell script was added to templates/scripts/ but not registered in script-manifest.json shellScripts array.' `
    -Action 'Add the script entry to script-manifest.json shellScripts array. Required fields: id, path, description, kind, exitPolicy, safeToRunInCI.' `
    -Safe $false

Add-Repair -Id 'component-manifest-missing' `
    -Pattern 'universe item not mapped|verify-components|shell:[\w-]+ not found' `
    -Cause 'A new script was added but not registered in component-manifest.json.' `
    -Action 'Add {"kind": "shell", "id": "<script-name-without-.sh>"} to the components array in component-manifest.json.' `
    -Safe $false

Add-Repair -Id 'doc-manifest-missing' `
    -Pattern 'verify-doc-manifest|literal.*not found in INDEX|INDEX.md count' `
    -Cause 'INDEX.md does not mention a new script name or has stale section counts.' `
    -Action 'Add the script name as a literal string in INDEX.md in the "Manifest-only" section and update the 19/19 and 40/40 counters.' `
    -Safe $false

Add-Repair -Id 'skills-drift' `
    -Pattern 'verify-skills-drift|verify-generated-drift|skills out of sync' `
    -Cause 'Generated skills in .claude/skills/ or .cursor/skills/ are out of sync with source/skills/.' `
    -Action 'Run: pwsh ./tools/sync-skills.ps1 to regenerate all skill files from source.' `
    -ApplyBlock {
        $syncTool = Join-Path $RepoRoot 'tools/sync-skills.ps1'
        if (Test-Path -LiteralPath $syncTool) {
            & $syncTool
            if ($LASTEXITCODE -ne 0) { throw 'sync-skills.ps1 failed' }
            return 'sync-skills.ps1 executed'
        }
        return 'sync-skills.ps1 not found — skipped'
    } `
    -Safe $true

Add-Repair -Id 'runtime-dispatcher-init' `
    -Pattern 'runtime-dispatcher|dispatcher: init.*must exit 0' `
    -Cause 'os-runtime.ps1 init command returns non-zero. Likely cause: sync-agent-adapters fails (sets $LASTEXITCODE=1) then os-doctor runs without explicit exit 0, leaving $LASTEXITCODE stale.' `
    -Action 'Check that os-doctor.ps1 and verify-agent-adapters.ps1 both call explicit exit 0 on success paths. Run: pwsh ./tools/verify-exit-codes.ps1.' `
    -Safe $false

# ── Detect applicable repairs ───────────────────────────────────────────────
$allSignals = ($failedNames -join ' ') + ' ' + $logText

foreach ($r in $repairs) {
    if ($allSignals -match $r.pattern) {
        $r.applicable = $true
    }
}

# If no artifacts loaded, mark all repairs as potentially applicable (diagnostic mode)
if ($failedNames.Count -eq 0 -and -not $logText) {
    if (-not $Json) { Write-Host 'INFO: No failure signals found. Showing all known repair patterns.' }
    foreach ($r in $repairs) { $r.applicable = $true }
}

# ── Apply safe repairs ──────────────────────────────────────────────────────
if ($Apply) {
    foreach ($r in $repairs) {
        if (-not $r.applicable) { continue }
        if (-not $r.safe -or -not $r.applyBlock) { continue }
        try {
            if ($DryRun) {
                [void]$applied.Add("[dry-run] would apply: $($r.id)")
                $r.applied = $true
            } else {
                $result = & $r.applyBlock
                [void]$applied.Add("applied $($r.id): $result")
                $r.applied = $true
            }
        } catch {
            [void]$warnings.Add("Failed to apply $($r.id): $($_.Exception.Message)")
        }
    }
}

$sw.Stop()

# ── Output ──────────────────────────────────────────────────────────────────
$applicableRepairs = @($repairs | Where-Object { $_.applicable })
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($applicableRepairs.Count -gt 0) { 'warn' } else { 'ok' }

$repairSummary = @($repairs | ForEach-Object {
    [ordered]@{
        id         = [string]$_.id
        applicable = [bool]$_.applicable
        safe       = [bool]$_.safe
        applied    = [bool]$_.applied
        cause      = [string]$_.cause
        action     = [string]$_.action
    }
})

$env = New-OsValidatorEnvelope -Tool 'ci-repair' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        applicableRepairs = $applicableRepairs.Count
        appliedRepairs    = $applied.Count
        repairs           = $repairSummary
    }))

# Write report file (always)
$reportPath = Join-Path $RepoRoot '.claude/ci-repair-report.json'
try {
    $env | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
} catch { }

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
} else {
    Write-Host 'ci-repair'
    Write-Host "Repo   : $RepoRoot"
    Write-Host "Mode   : $(if ($Apply) { 'apply' } else { 'diagnose (dry-run)' })"
    Write-Host ''
    foreach ($r in $repairs) {
        if (-not $r.applicable) { continue }
        $pfx = if ($r.applied) { 'APPLIED' } elseif ($r.safe) { 'READY  ' } else { 'MANUAL ' }
        Write-Host "${pfx}: [$($r.id)]"
        Write-Host "         Cause : $($r.cause)"
        Write-Host "         Action: $($r.action)"
        Write-Host ''
    }
    if ($applicableRepairs.Count -eq 0) {
        Write-Host 'No applicable repair patterns detected.'
    }
    if ($applied.Count -gt 0) {
        Write-Host "Applied: $($applied -join '; ')"
    }
    Write-Host "Report: $reportPath"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
