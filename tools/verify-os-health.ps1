# verify-os-health.ps1 — Aggregate Claude OS health verifier
# Run from repo root or any cwd (uses script location):
#   pwsh ./tools/verify-os-health.ps1
#   pwsh ./tools/verify-os-health.ps1 -Json
# Optional:
#   pwsh ./tools/verify-os-health.ps1 -SkipBootstrapSmoke -SkipBashSyntax

param(
    [switch]$SkipBootstrapSmoke,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash,
    [switch]$Strict,
    [switch]$Json,
    [switch]$WriteHistory
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Failures = @()
$Results = @()
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/os-remediation-guidance.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [int]$LatencyMs,
        [string]$Note = '',
        [string]$Reason = '',
        [string]$Impact = '',
        [string]$Remediation = '',
        [string]$StrictImpact = '',
        [string]$DocsLink = ''
    )
    $f = New-OsHealthStepFinding -StepName $Name -Status $Status -Note $Note
    if ($Reason) { $f.reason = $Reason }
    if ($Impact) { $f.impact = $Impact }
    if ($Remediation) { $f.remediation = $Remediation }
    if ($StrictImpact) { $f.strictImpact = $StrictImpact }
    if ($DocsLink) { $f.docsLink = $DocsLink }
    $script:Results += [pscustomobject]@{
        name           = $Name
        status         = $Status
        latency_ms     = $LatencyMs
        note           = $Note
        reason         = [string]$f.reason
        impact         = [string]$f.impact
        remediation    = [string]$f.remediation
        strictImpact   = [string]$f.strictImpact
        docsLink       = [string]$f.docsLink
    }
}

function Invoke-HealthStep {
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Script
        $sw.Stop()
        Add-Result -Name $Name -Status 'ok' -LatencyMs ([int]$sw.ElapsedMilliseconds)
    } catch {
        $sw.Stop()
        # Invariant: health output is concise; no raw stack traces or dumped JSON.
        $msg = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 240
        Add-Result -Name $Name -Status 'fail' -LatencyMs ([int]$sw.ElapsedMilliseconds) -Note $msg
        $script:Failures += $Name
    }
}

# In-process latency budgets (WARN soft, FAIL if wall-clock exceeds FailMs after completion).
# Does not preempt a hung child process; prefer keeping doctor bounded via os-doctor internals where possible.
function Invoke-HealthStepWithBudget {
    param(
        [string]$Name,
        [scriptblock]$Script,
        [int]$WarnMs = 10000,
        [int]$FailMs = 30000
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Script
        $sw.Stop()
        $ms = [int]$sw.ElapsedMilliseconds
        if ($ms -gt $FailMs) {
            $msg = Redact-SensitiveText -Text "${Name}: exceeded hard latency budget ${FailMs}ms (observed ${ms}ms)" -MaxLength 240
            Add-Result -Name $Name -Status 'fail' -LatencyMs $ms -Note $msg
            $script:Failures += $Name
            return
        }
        $note = ''
        $st = 'ok'
        if ($ms -gt $WarnMs) {
            $st = 'warn'
            $note = "soft latency budget ${WarnMs}ms exceeded (observed ${ms}ms)"
        }
        Add-Result -Name $Name -Status $st -LatencyMs $ms -Note $note
    } catch {
        $sw.Stop()
        $msg = Redact-SensitiveText -Text $_.Exception.Message -MaxLength 240
        Add-Result -Name $Name -Status 'fail' -LatencyMs ([int]$sw.ElapsedMilliseconds) -Note $msg
        $script:Failures += $Name
    }
}

function Test-PowerShellSyntax {
    param([string[]]$Files)
    foreach ($file in $Files) {
        if (-not (Test-Path -LiteralPath $file)) {
            throw "PowerShell file missing: $file"
        }
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $first = $errors[0]
            throw "Parse error in $(Split-Path $file -Leaf): $($first.Message)"
        }
    }
}

function Test-BashSyntax {
    if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
        throw 'bash not found on PATH'
    }
    Push-Location $RepoRoot
    try {
        & bash -n 'install.sh'
        if ($LASTEXITCODE -ne 0) { throw 'bash -n install.sh failed' }
        $scripts = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'templates/scripts') -Filter '*.sh' -File | Sort-Object Name)
        foreach ($script in $scripts) {
            & bash -n $script.FullName
            if ($LASTEXITCODE -ne 0) { throw "bash -n failed: $($script.Name)" }
        }
    } finally {
        Pop-Location
    }
}

function Test-BootstrapSmoke {
    $target = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-os-health-' + [System.Guid]::NewGuid().ToString('N'))
    try {
        & (Join-Path $RepoRoot 'init-project.ps1') -ProjectPath $target -SkipGitInit
        if ($LASTEXITCODE -ne 0) { throw 'init-project.ps1 returned a non-zero exit code' }
        $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'bootstrap-manifest.json') -Raw | ConvertFrom-Json
        $missing = @()
        foreach ($rel in @($manifest.projectBootstrap.criticalPaths)) {
            $path = Join-Path $target ([string]$rel)
            if (-not (Test-Path -LiteralPath $path)) { $missing += [string]$rel }
        }
        if ($missing.Count -gt 0) {
            throw "bootstrap smoke missing $($missing.Count) critical path(s)"
        }
    } finally {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-DocsIndexQuery {
    $raw = & (Join-Path $RepoRoot 'tools/query-docs-index.ps1') -Query health -Limit 1 -Json
    if ($LASTEXITCODE -ne 0) { throw 'query-docs-index.ps1 returned non-zero exit code' }
    $result = ($raw | Out-String) | ConvertFrom-Json
    if ([int]$result.count -lt 1) { throw 'query-docs-index.ps1 returned no health result' }
}

function Test-CapabilityRouter {
    $raw = & (Join-Path $RepoRoot 'tools/route-capability.ps1') -Query bootstrap -Limit 1 -Json
    if ($LASTEXITCODE -ne 0) { throw 'route-capability.ps1 returned non-zero exit code' }
    $result = ($raw | Out-String) | ConvertFrom-Json
    if ([int]$result.count -lt 1) { throw 'route-capability.ps1 returned no bootstrap route' }
}

function Test-WorkflowStatus {
    $raw = & (Join-Path $RepoRoot 'tools/workflow-status.ps1') -Phase verify -Json
    if ($LASTEXITCODE -ne 0) { throw 'workflow-status.ps1 returned non-zero exit code' }
    $result = ($raw | Out-String) | ConvertFrom-Json
    if ([int]$result.phaseCount -lt 1) { throw 'workflow-status.ps1 returned no workflow phase' }
}

function Test-RuntimeDispatcher {
    & (Join-Path $RepoRoot 'tools/verify-runtime-dispatcher.ps1')
}

function Test-RuntimeProfile {
    $raw = & (Join-Path $RepoRoot 'tools/runtime-profile.ps1') -Id core -Json
    if ($LASTEXITCODE -ne 0) { throw 'runtime-profile.ps1 returned non-zero exit code' }
    $result = ($raw | Out-String) | ConvertFrom-Json
    if ([int]$result.count -ne 1) { throw 'runtime-profile.ps1 did not return core profile' }
}

# Invariant: -RequireBash fails fast; otherwise missing bash auto-skips bash -n (local-first Windows).
$script:BashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)
if ($RequireBash -and -not $script:BashAvailable) {
    if (-not $Json) {
        Write-Host 'Bash: not found; required'
        Write-Host ''
    }
    if ($Json) {
        $pf = New-OsHealthStepFinding -StepName 'preconditions' -Status 'fail' -Note 'bash required on PATH when -RequireBash is set'
        $pre = New-OsHealthEnvelope -Strict $Strict.IsPresent -Checks @(
            [pscustomobject]@{
                name           = 'preconditions'
                status         = 'fail'
                latency_ms     = 0
                note           = 'bash required on PATH when -RequireBash is set'
                reason         = [string]$pf.reason
                impact         = [string]$pf.impact
                remediation    = [string]$pf.remediation
                strictImpact   = [string]$pf.strictImpact
                docsLink       = [string]$pf.docsLink
            }
        ) -FailureCount 1 -WarningCount 0 -RepoRoot $RepoRoot -TotalLatencyMs 0
        $pre | ConvertTo-Json -Depth 12 -Compress | Write-Output
        exit 1
    }
    throw 'verify-os-health: -RequireBash requires bash on PATH.'
}
# Same contract as os-validate-all.ps1 (RequireBash+bash-missing aborted above).
$script:EffectiveSkipBashSyntax = [bool]($SkipBashSyntax -or ((-not $script:BashAvailable) -and -not $RequireBash))

if (-not $Json) {
    Write-Host 'claude-operating-system health'
    Write-Host "Repo: $RepoRoot"
    if ($script:BashAvailable) {
        Write-Host 'Bash: available'
    } else {
        Write-Host 'Bash: not found; syntax check auto-skipped'
    }
    Write-Host ''
}

Invoke-HealthStep -Name 'safe-output-lib' -Script {
    . (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
    if (-not (Get-Command Redact-SensitiveText -ErrorAction SilentlyContinue)) { throw 'Redact-SensitiveText not defined after dot-sourcing safe-output.ps1' }
    if (-not (Get-Command Write-StatusLine -ErrorAction SilentlyContinue)) { throw 'Write-StatusLine not defined after dot-sourcing safe-output.ps1' }
    $probe = Redact-SensitiveText -Text 'Bearer pretendtokenvaluehere'
    if ($probe -notmatch 'REDACTED') { throw 'Redact-SensitiveText did not redact Bearer sample' }
    $p2 = Redact-SensitiveText -Text 'password=secret123'
    if ($p2 -notmatch 'REDACTED') { throw 'Redact-SensitiveText did not redact password sample' }
    $p3 = Redact-SensitiveText -Text "at line 1`nat System.Management.Automation" -MaxLength 400
    if ($p3 -match 'System\.Management') { throw 'Redact-SensitiveText should shorten stack-like lines' }
}

Invoke-HealthStep -Name 'git-hygiene' -Script {
    $gh = @{}
    if ($Strict) { $gh['Strict'] = $true }
    & (Join-Path $RepoRoot 'tools/verify-git-hygiene.ps1') @gh
}

Invoke-HealthStep -Name 'no-secrets' -Script {
    $ns = @('-Json')
    if ($Strict) { $ns += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-no-secrets.ps1') @ns 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-no-secrets failed' }
}

Invoke-HealthStep -Name 'manifest' -Script { & (Join-Path $RepoRoot 'tools/verify-bootstrap-manifest.ps1') }
Invoke-HealthStep -Name 'runtime-release' -Script { & (Join-Path $RepoRoot 'tools/verify-runtime-release.ps1') }
Invoke-HealthStep -Name 'json-contracts' -Script { & (Join-Path $RepoRoot 'tools/verify-json-contracts.ps1') }
Invoke-HealthStep -Name 'contract-tests' -Script { & (Join-Path $RepoRoot 'tools/run-contract-tests.ps1') }
Invoke-HealthStep -Name 'quality-gates' -Script { & (Join-Path $RepoRoot 'tools/verify-quality-gates.ps1') }
Invoke-HealthStep -Name 'deprecations' -Script { & (Join-Path $RepoRoot 'tools/verify-deprecations.ps1') -Strict }
Invoke-HealthStep -Name 'runtime-budget' -Script { & (Join-Path $RepoRoot 'tools/verify-runtime-budget.ps1') }
Invoke-HealthStep -Name 'context-economy' -Script { & (Join-Path $RepoRoot 'tools/verify-context-economy.ps1') }
Invoke-HealthStep -Name 'doc-contract-consistency' -Script { & (Join-Path $RepoRoot 'tools/verify-doc-contract-consistency.ps1') }
Invoke-HealthStep -Name 'compatibility' -Script {
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-compatibility.ps1') -Json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-compatibility failed' }
}
Invoke-HealthStep -Name 'lifecycle' -Script {
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-lifecycle.ps1') -Json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-lifecycle failed' }
}
Invoke-HealthStep -Name 'distribution' -Script {
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-distribution.ps1') -Json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-distribution failed' }
}
Invoke-HealthStep -Name 'upgrade-notes' -Script {
    $ua = @('-Json')
    if ($Strict) { $ua += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-upgrade-notes.ps1') @ua 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-upgrade-notes failed' }
}
Invoke-HealthStep -Name 'approval-log' -Script {
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-approval-log.ps1') -Json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-approval-log failed' }
}
Invoke-HealthStep -Name 'script-manifest' -Script {
    # Hashtable splat — array splat would pass '-Strict' positionally and break verify-script-manifest.ps1.
    $smArgs = @{}
    if ($Strict) { $smArgs['Strict'] = $true }
    & (Join-Path $RepoRoot 'tools/verify-script-manifest.ps1') @smArgs
}
Invoke-HealthStep -Name 'components' -Script {
    $vc = @('-Json')
    if ($Strict) { $vc += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-components.ps1') @vc 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-components failed' }
}
Invoke-HealthStep -Name 'agent-adapters' -Script { & (Join-Path $RepoRoot 'tools/verify-agent-adapters.ps1') }
Invoke-HealthStep -Name 'runtime-profiles' -Script { & (Join-Path $RepoRoot 'tools/verify-runtime-profiles.ps1') }
Invoke-HealthStep -Name 'runtime-profile' -Script { Test-RuntimeProfile }
Invoke-HealthStep -Name 'session-memory' -Script { & (Join-Path $RepoRoot 'tools/verify-session-memory.ps1') }
Invoke-HealthStep -Name 'playbooks' -Script {
    $pa = @('-Json')
    if ($Strict) { $pa += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-playbooks.ps1') @pa 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-playbooks failed' }
}
Invoke-HealthStep -Name 'recipes' -Script {
    $ra = @('-Json')
    if ($Strict) { $ra += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-recipes.ps1') @ra 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-recipes failed' }
}
Invoke-HealthStep -Name 'skills-manifest' -Script {
    $ma = @('-Json')
    if ($Strict) { $ma += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-skills-manifest.ps1') @ma 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-skills-manifest failed' }
}
Invoke-HealthStep -Name 'skills' -Script {
    & (Join-Path $RepoRoot 'tools/verify-skills.ps1')
    $structArgs = @('-Json')
    if ($Strict) { $structArgs += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-skills-structure.ps1') @structArgs 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-skills-structure failed' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-skills-economy.ps1') -Json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-skills-economy failed' }
    $driftA = @('-Json')
    if ($Strict) { $driftA += '-Strict' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/verify-skills-drift.ps1') @driftA 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'verify-skills-drift failed' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/test-skills.ps1') @() 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'test-skills failed' }
}
Invoke-HealthStep -Name 'docs' -Script { & (Join-Path $RepoRoot 'tools/verify-doc-manifest.ps1') }
Invoke-HealthStep -Name 'docs-index' -Script { & (Join-Path $RepoRoot 'tools/verify-docs-index.ps1') }
Invoke-HealthStep -Name 'docs-index-query' -Script { Test-DocsIndexQuery }
Invoke-HealthStep -Name 'capabilities' -Script { & (Join-Path $RepoRoot 'tools/verify-capabilities.ps1') }
Invoke-HealthStep -Name 'capability-router' -Script { Test-CapabilityRouter }
Invoke-HealthStep -Name 'workflow' -Script { & (Join-Path $RepoRoot 'tools/verify-workflow-manifest.ps1') }
Invoke-HealthStep -Name 'workflow-status' -Script { Test-WorkflowStatus }
Invoke-HealthStep -Name 'runtime-dispatcher' -Script { Test-RuntimeDispatcher }
Invoke-HealthStep -Name 'exit-code-hygiene' -Script { & (Join-Path $RepoRoot 'tools/verify-exit-codes.ps1') }
Invoke-HealthStep -Name 'checklists' -Script { & (Join-Path $RepoRoot 'tools/verify-checklists.ps1') }
Invoke-HealthStepWithBudget -Name 'doctor' -WarnMs 10000 -FailMs 30000 -Script {
    $doctorParams = @{ Json = $true }
    if ($script:EffectiveSkipBashSyntax) { $doctorParams['SkipBashSyntax'] = $true }
    if ($RequireBash) { $doctorParams['RequireBash'] = $true }
    $raw = & (Join-Path $RepoRoot 'tools/os-doctor.ps1') @doctorParams
    if ($LASTEXITCODE -ne 0) { throw 'os-doctor.ps1 returned non-zero exit code' }
    $result = ($raw | Out-String) | ConvertFrom-Json
    if ($result.status -eq 'fail') { throw 'os-doctor.ps1 reported blocking failures' }
}
Invoke-HealthStep -Name 'powershell-syntax' -Script {
    $psSyntaxFiles = @(
        (Join-Path $RepoRoot 'install.ps1'),
        (Join-Path $RepoRoot 'init-project.ps1'),
        (Join-Path $RepoRoot 'tools/lib/safe-output.ps1'),
        (Join-Path $RepoRoot 'tools/verify-agent-adapters.ps1'),
        (Join-Path $RepoRoot 'tools/verify-bootstrap-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/verify-bootstrap-examples.ps1'),
        (Join-Path $RepoRoot 'tools/evaluate-quality-gate.ps1'),
        (Join-Path $RepoRoot 'tools/verify-quality-gates.ps1'),
        (Join-Path $RepoRoot 'tools/verify-deprecations.ps1'),
        (Join-Path $RepoRoot 'tools/verify-doc-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/verify-docs-index.ps1'),
        (Join-Path $RepoRoot 'tools/query-docs-index.ps1'),
        (Join-Path $RepoRoot 'tools/verify-capabilities.ps1'),
        (Join-Path $RepoRoot 'tools/route-capability.ps1'),
        (Join-Path $RepoRoot 'tools/verify-workflow-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/workflow-status.ps1'),
        (Join-Path $RepoRoot 'tools/runtime-profile.ps1'),
        (Join-Path $RepoRoot 'tools/session-prime.ps1'),
        (Join-Path $RepoRoot 'tools/session-absorb.ps1'),
        (Join-Path $RepoRoot 'tools/session-digest.ps1'),
        (Join-Path $RepoRoot 'tools/verify-runtime-profiles.ps1'),
        (Join-Path $RepoRoot 'tools/verify-playbooks.ps1'),
        (Join-Path $RepoRoot 'tools/verify-recipes.ps1'),
        (Join-Path $RepoRoot 'tools/verify-session-memory.ps1'),
        (Join-Path $RepoRoot 'tools/verify-checklists.ps1'),
        (Join-Path $RepoRoot 'tools/verify-json-contracts.ps1'),
        (Join-Path $RepoRoot 'tools/invoke-safe-apply.ps1'),
        (Join-Path $RepoRoot 'tools/run-contract-tests.ps1'),
        (Join-Path $RepoRoot 'tools/verify-runtime-release.ps1'),
        (Join-Path $RepoRoot 'tools/os-doctor.ps1'),
        (Join-Path $RepoRoot 'tools/os-runtime.ps1'),
        (Join-Path $RepoRoot 'tools/os-update-project.ps1'),
        (Join-Path $RepoRoot 'tools/os-validate-all.ps1'),
        (Join-Path $RepoRoot 'tools/verify-skills.ps1'),
        (Join-Path $RepoRoot 'tools/verify-skills-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/verify-skills-structure.ps1'),
        (Join-Path $RepoRoot 'tools/verify-skills-drift.ps1'),
        (Join-Path $RepoRoot 'tools/test-skills.ps1'),
        (Join-Path $RepoRoot 'tools/verify-skills-economy.ps1'),
        (Join-Path $RepoRoot 'tools/sync-skills.ps1'),
        (Join-Path $RepoRoot 'tools/verify-os-health.ps1'),
        (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1'),
        (Join-Path $RepoRoot 'tools/verify-git-hygiene.ps1'),
        (Join-Path $RepoRoot 'tools/verify-no-secrets.ps1'),
        (Join-Path $RepoRoot 'tools/verify-runtime-dispatcher.ps1'),
        (Join-Path $RepoRoot 'tools/init-os-runtime.ps1'),
        (Join-Path $RepoRoot 'tools/os-validate.ps1'),
        (Join-Path $RepoRoot 'tools/sync-agent-adapters.ps1'),
        (Join-Path $RepoRoot 'tools/verify-agent-adapter-drift.ps1'),
        (Join-Path $RepoRoot 'tools/verify-context-economy.ps1'),
        (Join-Path $RepoRoot 'tools/verify-components.ps1'),
        (Join-Path $RepoRoot 'tools/verify-compatibility.ps1'),
        (Join-Path $RepoRoot 'tools/verify-lifecycle.ps1'),
        (Join-Path $RepoRoot 'tools/verify-distribution.ps1'),
        (Join-Path $RepoRoot 'tools/verify-upgrade-notes.ps1'),
        (Join-Path $RepoRoot 'tools/verify-approval-log.ps1'),
        (Join-Path $RepoRoot 'tools/append-approval-log.ps1'),
        (Join-Path $RepoRoot 'tools/build-distribution.ps1'),
        (Join-Path $RepoRoot 'tools/verify-doc-contract-consistency.ps1'),
        (Join-Path $RepoRoot 'tools/verify-runtime-budget.ps1'),
        (Join-Path $RepoRoot 'tools/verify-script-manifest.ps1'),
        (Join-Path $RepoRoot 'tools/write-validation-history.ps1')
    )
    Test-PowerShellSyntax -Files $psSyntaxFiles
}

if (-not $SkipBootstrapSmoke) {
    Invoke-HealthStep -Name 'bootstrap-real-smoke' -Script { Test-BootstrapSmoke }
} else {
    Add-Result -Name 'bootstrap-real-smoke' -Status 'skip' -LatencyMs 0 -Note 'skipped by flag'
}

if (-not $script:EffectiveSkipBashSyntax) {
    Invoke-HealthStep -Name 'bash-syntax' -Script { Test-BashSyntax }
} else {
    $skipReason = if ($SkipBashSyntax) { 'skipped by flag' } else { 'bash not found on PATH' }
    Add-Result -Name 'bash-syntax' -Status 'skip' -LatencyMs 0 -Note $skipReason
}

$totalMs = [int]($Results | Measure-Object -Property latency_ms -Sum).Sum
$warnCount = @($Results | Where-Object { $_.status -eq 'warn' }).Count
$failCount = $Failures.Count

if ($WriteHistory) {
    $histSt = if ($failCount -gt 0) { 'fail' } elseif ($warnCount -gt 0) { 'warn' } else { 'ok' }
    $histWarns = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($Results | Where-Object { $_.status -eq 'warn' })) {
        $n = if ($r.note) { [string]$r.note } else { '' }
        [void]$histWarns.Add((Redact-SensitiveText -Text ("$($r.name): $n").TrimEnd(': ') -MaxLength 400))
    }
    $histFails = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @($Failures)) { [void]$histFails.Add([string]$f) }
    $rec = [ordered]@{
        timestamp  = (Get-Date).ToUniversalTime().ToString('o')
        event      = 'validation'
        tool       = 'verify-os-health'
        profile    = ''
        status     = $histSt
        durationMs = $totalMs
        warnings   = @($histWarns)
        failures   = @($histFails)
    }
    & (Join-Path $RepoRoot 'tools/write-validation-history.ps1') -Record ($rec | ConvertTo-Json -Depth 8 -Compress) -RepoRoot $RepoRoot -Quiet
}

if ($Json) {
    $envelope = New-OsHealthEnvelope -Strict $Strict.IsPresent -Checks @($Results) -FailureCount $failCount -WarningCount $warnCount -RepoRoot $RepoRoot -TotalLatencyMs $totalMs
    $envelope | ConvertTo-Json -Depth 14 -Compress | Write-Output
}

if (-not $Json) {
    Write-Host ''
    Write-Host 'Summary:'
    foreach ($r in $Results) {
        $line = "  $($r.status.ToUpper().PadRight(4)) $($r.name) ($($r.latency_ms) ms)"
        if ($r.note) { $line += " - $(Redact-SensitiveText -Text $r.note -MaxLength 180)" }
        Write-Host $line
        if ([string]$r.status -in @('warn', 'fail', 'skip')) {
            if ($r.remediation) {
                Write-Host ("       remediation: {0}" -f (Redact-SensitiveText -Text ([string]$r.remediation) -MaxLength 220))
            }
            if ($r.docsLink) {
                Write-Host ("       docs: {0}" -f (Redact-SensitiveText -Text ([string]$r.docsLink) -MaxLength 120))
            }
        }
    }
    Write-Host ''
    Write-Host "Health checks: $($Results.Count), failures: $failCount, warnings: $warnCount, total: $totalMs ms"
}

if ($failCount -gt 0) {
    if ($Json) { exit 1 }
    throw "Claude OS health failed: $($Failures -join ', ')"
}
if ($Strict -and $warnCount -gt 0) {
    if ($Json) { exit 1 }
    $wn = @($Results | Where-Object { $_.status -eq 'warn' } | ForEach-Object { $_.name }) -join ', '
    throw "Claude OS health strict mode: warning(s) not permitted on check(s): $wn"
}

if (-not $Json) {
    Write-Host 'Claude OS health passed.'
}
if ($Json) {
    exit 0
}
