# os-validate.ps1 — Profiled validation orchestrator (quick / standard / strict)
#   pwsh ./tools/os-validate.ps1 -Profile quick [-Json] [-SkipBashSyntax] [-WriteHistory]
# strict ends with os-validate-all.ps1 -Strict (adds -RequireBash when bash is on PATH and -SkipBashSyntax is not set)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('quick', 'standard', 'strict')]
    [string]$Profile,

    [switch]$Json,
    [switch]$SkipBashSyntax,
    [switch]$RequireBash,
    [switch]$WriteHistory
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stepResults = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-PwshTool {
    param(
        [string]$RelativeTool,
        [string[]]$ArgList
    )
    $p = Join-Path $RepoRoot $RelativeTool
    $null = & pwsh -NoProfile -File $p @ArgList 2>$null
    return [int]$LASTEXITCODE
}

function Get-OsToolJsonStatus {
    param([string]$RelativeTool, [string[]]$ArgList)
    $p = Join-Path $RepoRoot $RelativeTool
    $raw = @(& pwsh -NoProfile -File $p @ArgList 2>$null)
    $line = $raw | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
    if (-not $line) { $line = $raw[-1] }
    try {
        $o = $line | ConvertFrom-Json
        return [string]$o.status
    }
    catch {
        return 'ok'
    }
}

function Add-Step {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    [void]$script:stepResults.Add([ordered]@{ name = $Name; status = $Status; detail = (Redact-SensitiveText -Text $Detail -MaxLength 220) })
}

function Invoke-JsonTool {
    param([string]$Rel, [string]$StepName)
    $code = Invoke-PwshTool -RelativeTool $Rel -ArgList @('-Json')
    if ($code -ne 0) {
        [void]$failures.Add("$StepName exit $code")
        Add-Step -Name $StepName -Status 'fail' -Detail "exit $code"
        return
    }
    $st = Get-OsToolJsonStatus -RelativeTool $Rel -ArgList @('-Json')
    if ($st -eq 'fail') {
        [void]$failures.Add("$StepName reported fail")
        Add-Step -Name $StepName -Status 'fail'
    }
    elseif ($st -eq 'warn' -or $st -eq 'skip') {
        [void]$warnings.Add("$StepName status=$st (not treated as passed)")
        Add-Step -Name $StepName -Status $st
    }
    else {
        Add-Step -Name $StepName -Status 'ok'
    }
}

foreach ($pair in @(
        @{ rel = 'tools/verify-autonomy-policy.ps1'; name = 'verify-autonomy-policy' }
        @{ rel = 'tools/verify-runtime-budget.ps1'; name = 'verify-runtime-budget' }
        @{ rel = 'tools/verify-context-economy.ps1'; name = 'verify-context-economy' }
        @{ rel = 'tools/verify-compatibility.ps1'; name = 'verify-compatibility' }
        @{ rel = 'tools/verify-lifecycle.ps1'; name = 'verify-lifecycle' }
        @{ rel = 'tools/verify-distribution.ps1'; name = 'verify-distribution' }
        @{ rel = 'tools/verify-doc-contract-consistency.ps1'; name = 'verify-doc-contract-consistency' }
        @{ rel = 'tools/verify-quality-gates.ps1'; name = 'verify-quality-gates' }
    )) {
    Invoke-JsonTool -Rel $pair.rel -StepName $pair.name
}

$smfArgs = @('-Json')
if ($Profile -eq 'strict') { $smfArgs += '-Strict' }
$smfCode = Invoke-PwshTool -RelativeTool 'tools/verify-script-manifest.ps1' -ArgList $smfArgs
if ($smfCode -ne 0) {
    [void]$failures.Add('verify-script-manifest exit non-zero')
    Add-Step -Name 'verify-script-manifest' -Status 'fail' -Detail "exit $smfCode"
}
else {
    $smfSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-script-manifest.ps1' -ArgList $smfArgs
    if ($smfSt -eq 'fail') {
        [void]$failures.Add('verify-script-manifest reported fail')
        Add-Step -Name 'verify-script-manifest' -Status 'fail'
    }
    elseif ($smfSt -eq 'warn' -or $smfSt -eq 'skip') {
        [void]$warnings.Add("verify-script-manifest status=$smfSt (not treated as passed)")
        Add-Step -Name 'verify-script-manifest' -Status $smfSt
    }
    else {
        Add-Step -Name 'verify-script-manifest' -Status 'ok'
    }
}

$vcArgs = @('-Json')
if ($Profile -eq 'strict') { $vcArgs += '-Strict' }
$vcCode = Invoke-PwshTool -RelativeTool 'tools/verify-components.ps1' -ArgList $vcArgs
if ($vcCode -ne 0) {
    [void]$failures.Add('verify-components exit non-zero')
    Add-Step -Name 'verify-components' -Status 'fail' -Detail "exit $vcCode"
}
else {
    $vcSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-components.ps1' -ArgList $vcArgs
    if ($vcSt -eq 'fail') {
        [void]$failures.Add('verify-components reported fail')
        Add-Step -Name 'verify-components' -Status 'fail'
    }
    elseif ($vcSt -eq 'warn' -or $vcSt -eq 'skip') {
        [void]$warnings.Add("verify-components status=$vcSt (not treated as passed)")
        Add-Step -Name 'verify-components' -Status $vcSt
    }
    else {
        Add-Step -Name 'verify-components' -Status 'ok'
    }
}

$mfSkillsArgs = @('-Json')
if ($Profile -eq 'strict') { $mfSkillsArgs += '-Strict' }
$mfCode = Invoke-PwshTool -RelativeTool 'tools/verify-skills-manifest.ps1' -ArgList $mfSkillsArgs
if ($mfCode -ne 0) {
    [void]$failures.Add('verify-skills-manifest exit non-zero')
    Add-Step -Name 'verify-skills-manifest' -Status 'fail' -Detail "exit $mfCode"
}
else {
    $mfSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-skills-manifest.ps1' -ArgList $mfSkillsArgs
    if ($mfSt -eq 'fail') {
        [void]$failures.Add('verify-skills-manifest reported fail')
        Add-Step -Name 'verify-skills-manifest' -Status 'fail'
    }
    elseif ($mfSt -eq 'warn' -or $mfSt -eq 'skip') {
        [void]$warnings.Add("verify-skills-manifest status=$mfSt (not treated as passed)")
        Add-Step -Name 'verify-skills-manifest' -Status $mfSt
    }
    else {
        Add-Step -Name 'verify-skills-manifest' -Status 'ok'
    }
}
$structArgs = @('-Json')
if ($Profile -eq 'strict') { $structArgs += '-Strict' }
$structCode = Invoke-PwshTool -RelativeTool 'tools/verify-skills-structure.ps1' -ArgList $structArgs
if ($structCode -ne 0) {
    [void]$failures.Add('verify-skills-structure exit non-zero')
    Add-Step -Name 'verify-skills-structure' -Status 'fail' -Detail "exit $structCode"
}
else {
    if ($Profile -eq 'strict') {
        $sst = Get-OsToolJsonStatus -RelativeTool 'tools/verify-skills-structure.ps1' -ArgList $structArgs
        if ($sst -eq 'fail') {
            [void]$failures.Add('verify-skills-structure reported fail')
            Add-Step -Name 'verify-skills-structure' -Status 'fail'
        }
        elseif ($sst -eq 'warn' -or $sst -eq 'skip') {
            [void]$warnings.Add("verify-skills-structure status=$sst")
            Add-Step -Name 'verify-skills-structure' -Status $sst
        }
        else {
            Add-Step -Name 'verify-skills-structure' -Status 'ok'
        }
    }
    else {
        Add-Step -Name 'verify-skills-structure' -Status 'ok'
    }
}

$vsk = Invoke-PwshTool -RelativeTool 'tools/verify-skills.ps1' -ArgList @()
if ($vsk -ne 0) {
    [void]$failures.Add('verify-skills exit non-zero')
    Add-Step -Name 'verify-skills' -Status 'fail' -Detail "exit $vsk"
}
else {
    Add-Step -Name 'verify-skills' -Status 'ok'
}

$pbArgs = @('-Json')
if ($Profile -eq 'strict') { $pbArgs += '-Strict' }
$pbCode = Invoke-PwshTool -RelativeTool 'tools/verify-playbooks.ps1' -ArgList $pbArgs
if ($pbCode -ne 0) {
    [void]$failures.Add('verify-playbooks exit non-zero')
    Add-Step -Name 'verify-playbooks' -Status 'fail' -Detail "exit $pbCode"
}
else {
    $pbSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-playbooks.ps1' -ArgList $pbArgs
    if ($pbSt -eq 'fail') {
        [void]$failures.Add('verify-playbooks reported fail')
        Add-Step -Name 'verify-playbooks' -Status 'fail'
    }
    elseif ($pbSt -eq 'warn' -or $pbSt -eq 'skip') {
        [void]$warnings.Add("verify-playbooks status=$pbSt (not treated as passed)")
        Add-Step -Name 'verify-playbooks' -Status $pbSt
    }
    else {
        Add-Step -Name 'verify-playbooks' -Status 'ok'
    }
}

$alCode = Invoke-PwshTool -RelativeTool 'tools/verify-approval-log.ps1' -ArgList @('-Json')
if ($alCode -ne 0) {
    [void]$failures.Add('verify-approval-log exit non-zero')
    Add-Step -Name 'verify-approval-log' -Status 'fail' -Detail "exit $alCode"
}
else {
    $alSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-approval-log.ps1' -ArgList @('-Json')
    if ($alSt -eq 'fail') {
        [void]$failures.Add('verify-approval-log reported fail')
        Add-Step -Name 'verify-approval-log' -Status 'fail'
    }
    elseif ($alSt -eq 'warn' -or $alSt -eq 'skip') {
        [void]$warnings.Add("verify-approval-log status=$alSt")
        Add-Step -Name 'verify-approval-log' -Status $alSt
    }
    else {
        Add-Step -Name 'verify-approval-log' -Status 'ok'
    }
}

$recArgs = @('-Json')
if ($Profile -eq 'strict') { $recArgs += '-Strict' }
$recCode = Invoke-PwshTool -RelativeTool 'tools/verify-recipes.ps1' -ArgList $recArgs
if ($recCode -ne 0) {
    [void]$failures.Add('verify-recipes exit non-zero')
    Add-Step -Name 'verify-recipes' -Status 'fail' -Detail "exit $recCode"
}
else {
    $recSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-recipes.ps1' -ArgList $recArgs
    if ($recSt -eq 'fail') {
        [void]$failures.Add('verify-recipes reported fail')
        Add-Step -Name 'verify-recipes' -Status 'fail'
    }
    elseif ($recSt -eq 'warn' -or $recSt -eq 'skip') {
        [void]$warnings.Add("verify-recipes status=$recSt (not treated as passed)")
        Add-Step -Name 'verify-recipes' -Status $recSt
    }
    else {
        Add-Step -Name 'verify-recipes' -Status 'ok'
    }
}

foreach ($pair in @(
        @{ rel = 'tools/verify-json-contracts.ps1'; name = 'verify-json-contracts' }
        @{ rel = 'tools/verify-bootstrap-manifest.ps1'; name = 'verify-bootstrap-manifest' }
    )) {
    $c = Invoke-PwshTool -RelativeTool $pair.rel -ArgList @()
    if ($c -ne 0) {
        [void]$failures.Add("$($pair.name) exit $c")
        Add-Step -Name $pair.name -Status 'fail' -Detail "exit $c"
    }
    else {
        Add-Step -Name $pair.name -Status 'ok'
    }
}

if ($Profile -in @('standard', 'strict')) {
    Invoke-JsonTool -Rel 'tools/verify-skills-economy.ps1' -StepName 'verify-skills-economy'
    $skillDriftArgs = @('-Json')
    if ($Profile -eq 'strict') { $skillDriftArgs += '-Strict' }
    $sdc = Invoke-PwshTool -RelativeTool 'tools/verify-skills-drift.ps1' -ArgList $skillDriftArgs
    if ($sdc -ne 0) {
        [void]$failures.Add('verify-skills-drift exit non-zero')
        Add-Step -Name 'verify-skills-drift' -Status 'fail' -Detail "exit $sdc"
    }
    else {
        $sdst = Get-OsToolJsonStatus -RelativeTool 'tools/verify-skills-drift.ps1' -ArgList $skillDriftArgs
        if ($sdst -eq 'fail') {
            [void]$failures.Add('verify-skills-drift reported fail')
            Add-Step -Name 'verify-skills-drift' -Status 'fail'
        }
        elseif ($sdst -eq 'warn' -or $sdst -eq 'skip') {
            [void]$warnings.Add("verify-skills-drift status=$sdst")
            Add-Step -Name 'verify-skills-drift' -Status $sdst
        }
        else {
            Add-Step -Name 'verify-skills-drift' -Status 'ok'
        }
    }

    $ghc = Invoke-PwshTool -RelativeTool 'tools/verify-git-hygiene.ps1' -ArgList @('-Json', '-WarnIfNoGit')
    if ($ghc -ne 0) {
        [void]$failures.Add('verify-git-hygiene exit non-zero')
        Add-Step -Name 'verify-git-hygiene' -Status 'fail'
    }
    else {
        $gst = Get-OsToolJsonStatus -RelativeTool 'tools/verify-git-hygiene.ps1' -ArgList @('-Json', '-WarnIfNoGit')
        if ($gst -eq 'warn') { [void]$warnings.Add('git-hygiene warn (e.g. missing .git or dirty tree)') }
        Add-Step -Name 'verify-git-hygiene' -Status $(if ($gst) { $gst } else { 'ok' })
    }

    $secArgs = @('-Json')
    if ($Profile -eq 'strict') { $secArgs += '-Strict' }
    $secC = Invoke-PwshTool -RelativeTool 'tools/verify-no-secrets.ps1' -ArgList $secArgs
    if ($secC -ne 0) {
        [void]$failures.Add('verify-no-secrets exit non-zero')
        Add-Step -Name 'verify-no-secrets' -Status 'fail' -Detail "exit $secC"
    }
    else {
        $secSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-no-secrets.ps1' -ArgList $secArgs
        if ($secSt -eq 'fail') {
            [void]$failures.Add('verify-no-secrets reported fail')
            Add-Step -Name 'verify-no-secrets' -Status 'fail'
        }
        elseif ($secSt -eq 'warn' -or $secSt -eq 'skip') {
            [void]$warnings.Add("verify-no-secrets status=$secSt")
            Add-Step -Name 'verify-no-secrets' -Status $secSt
        }
        else {
            Add-Step -Name 'verify-no-secrets' -Status 'ok'
        }
    }

    $upArgs = @('-Json')
    if ($Profile -eq 'strict') { $upArgs += '-Strict' }
    $upC = Invoke-PwshTool -RelativeTool 'tools/verify-upgrade-notes.ps1' -ArgList $upArgs
    if ($upC -ne 0) {
        [void]$failures.Add('verify-upgrade-notes exit non-zero')
        Add-Step -Name 'verify-upgrade-notes' -Status 'fail' -Detail "exit $upC"
    }
    else {
        $upSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-upgrade-notes.ps1' -ArgList $upArgs
        if ($upSt -eq 'fail') {
            [void]$failures.Add('verify-upgrade-notes reported fail')
            Add-Step -Name 'verify-upgrade-notes' -Status 'fail'
        }
        elseif ($upSt -eq 'warn' -or $upSt -eq 'skip') {
            [void]$warnings.Add("verify-upgrade-notes status=$upSt")
            Add-Step -Name 'verify-upgrade-notes' -Status $upSt
        }
        else {
            Add-Step -Name 'verify-upgrade-notes' -Status 'ok'
        }
    }

    foreach ($rel in @(
            'tools/verify-docs-index.ps1',
            'tools/verify-session-memory.ps1',
            'tools/verify-agent-adapters.ps1',
            'tools/verify-doc-manifest.ps1',
            'tools/verify-workflow-manifest.ps1',
            'tools/verify-capabilities.ps1',
            'tools/test-skills.ps1',
            'tools/verify-runtime-profiles.ps1'
        )) {
        $n = Split-Path $rel -Leaf
        $c = Invoke-PwshTool -RelativeTool $rel -ArgList @()
        if ($c -ne 0) {
            [void]$failures.Add("$n exit $c")
            Add-Step -Name $n -Status 'fail'
        }
        else { Add-Step -Name $n -Status 'ok' }
    }

    $driftArgs = @('-Json')
    if ($Profile -eq 'strict') { $driftArgs += '-FailOnDrift' }
    $dc = Invoke-PwshTool -RelativeTool 'tools/verify-agent-adapter-drift.ps1' -ArgList $driftArgs
    if ($dc -ne 0) {
        [void]$failures.Add('verify-agent-adapter-drift failed')
        Add-Step -Name 'verify-agent-adapter-drift' -Status 'fail'
    }
    else {
        $dst = Get-OsToolJsonStatus -RelativeTool 'tools/verify-agent-adapter-drift.ps1' -ArgList $driftArgs
        if ($dst -eq 'warn') { [void]$warnings.Add('adapter drift warning') }
        Add-Step -Name 'verify-agent-adapter-drift' -Status $(if ($dst) { $dst } else { 'ok' })
    }

    $docParams = @()
    if ($Json) { $docParams += '-Json' }
    if ($SkipBashSyntax) { $docParams += '-SkipBashSyntax' }
    if ($RequireBash) { $docParams += '-RequireBash' }
    $dc2 = Invoke-PwshTool -RelativeTool 'tools/os-doctor.ps1' -ArgList $docParams
    if ($dc2 -ne 0) {
        [void]$failures.Add('os-doctor failed')
        Add-Step -Name 'os-doctor' -Status 'fail'
    }
    else { Add-Step -Name 'os-doctor' -Status 'ok' }
}

if ($Profile -eq 'strict') {
    $depArgs = @('-Json', '-Strict')
    $depCode = Invoke-PwshTool -RelativeTool 'tools/verify-deprecations.ps1' -ArgList $depArgs
    if ($depCode -ne 0) {
        [void]$failures.Add('verify-deprecations exit non-zero')
        Add-Step -Name 'verify-deprecations' -Status 'fail' -Detail "exit $depCode"
    }
    else {
        $depSt = Get-OsToolJsonStatus -RelativeTool 'tools/verify-deprecations.ps1' -ArgList $depArgs
        if ($depSt -eq 'fail') {
            [void]$failures.Add('verify-deprecations reported fail')
            Add-Step -Name 'verify-deprecations' -Status 'fail'
        }
        elseif ($depSt -eq 'warn' -or $depSt -eq 'skip') {
            [void]$warnings.Add("verify-deprecations status=$depSt")
            Add-Step -Name 'verify-deprecations' -Status $depSt
        }
        else {
            Add-Step -Name 'verify-deprecations' -Status 'ok'
        }
    }

    $va = @('-Strict')
    if ($Json) { $va += '-Json' }
    if ($SkipBashSyntax) { $va += '-SkipBashSyntax' }
    elseif (Get-Command bash -ErrorAction SilentlyContinue) { $va += '-RequireBash' }
    if ($RequireBash) { $va += '-RequireBash' }
    if ($WriteHistory) { $va += '-WriteHistory' }
    $ac = Invoke-PwshTool -RelativeTool 'tools/os-validate-all.ps1' -ArgList $va
    if ($ac -ne 0) {
        [void]$failures.Add('os-validate-all strict failed')
        Add-Step -Name 'os-validate-all' -Status 'fail'
    }
    else { Add-Step -Name 'os-validate-all' -Status 'ok' }
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'os-validate' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($stepResults) -Warnings @($warnings) -Failures @($failures) -Findings @(@([ordered]@{ profile = $Profile }))

if ($WriteHistory) {
    $rec = @{
        timestamp  = (Get-Date).ToUniversalTime().ToString('o')
        event      = 'validation'
        tool       = 'os-validate'
        profile    = $Profile
        status     = $st
        durationMs = [int]$sw.ElapsedMilliseconds
        warnings   = @($warnings)
        failures   = @($failures)
    } | ConvertTo-Json -Compress -Depth 6
    & (Join-Path $RepoRoot 'tools/write-validation-history.ps1') -Record $rec -RepoRoot $RepoRoot -Quiet
}

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "os-validate [$Profile]: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
# Non-zero exit when any step produced warn/skip-class outcomes so shells/CI do not treat warn as green.
if ($st -eq 'warn') { exit 1 }
exit 0
