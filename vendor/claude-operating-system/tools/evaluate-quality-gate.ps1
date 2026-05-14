# evaluate-quality-gate.ps1 — Run validators declared in quality-gates/<domain>.json and apply gate policy
#   pwsh ./tools/evaluate-quality-gate.ps1 -Gate docs [-Strict] [-Json]

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('docs', 'skills', 'release', 'bootstrap', 'adapters', 'security', 'strict')]
    [string]$Gate,

    [switch]$Strict,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

function Get-LastJsonObjectFromLines {
    param([string[]]$Lines)
    $candidates = @($Lines | Where-Object { $_ -match '^\s*\{' })
    if ($candidates.Count -eq 0) { return $null }
    $js = $candidates[-1]
    try { return ($js | ConvertFrom-Json) } catch { return $null }
}

function Get-OutcomeFromRun {
    param(
        [string[]]$Lines,
        [int]$ExitCode,
        [bool]$EmitJson
    )
    $warnList = [System.Collections.Generic.List[string]]::new()
    if (-not $EmitJson) {
        return [ordered]@{
            status   = $(if ($ExitCode -eq 0) { 'ok' } else { 'fail' })
            warnings = @($warnList)
        }
    }
    $o = Get-LastJsonObjectFromLines -Lines $Lines
    if (-not $o) {
        return [ordered]@{
            status   = $(if ($ExitCode -eq 0) { 'ok' } else { 'fail' })
            warnings = @($warnList)
        }
    }
    $st = if ($o.PSObject.Properties.Name -contains 'status') { [string]$o.status } else { '' }
    if (-not $st) { $st = if ($ExitCode -eq 0) { 'ok' } else { 'fail' } }

    if ($o.PSObject.Properties.Name -contains 'warnings') {
        $w = $o.warnings
        if ($w -is [System.Array] -or $w -is [System.Collections.IList]) {
            foreach ($x in @($w)) { [void]$warnList.Add([string]$x) }
        }
        elseif ($null -ne $w -and $w -is [int]) {
            if ([int]$w -gt 0 -and $st -eq 'ok') { $st = 'warn' }
        }
    }

    if ($o.PSObject.Properties.Name -contains 'name' -and [string]$o.name -eq 'os-validate-all') {
        if ($st -eq 'ok' -and $o.PSObject.Properties.Name -contains 'warnings' -and $o.warnings -is [int] -and [int]$o.warnings -gt 0) {
            $st = 'warn'
        }
    }

    return [ordered]@{ status = $st; warnings = @($warnList) }
}

function Test-WarningAllowed {
    param([string]$Text, [string[]]$Allowed)
    $t = $Text.ToLowerInvariant()
    foreach ($a in $Allowed) {
        if ([string]::IsNullOrWhiteSpace($a)) { continue }
        if ($t.Contains($a.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Test-GateStatusPass {
    param([string]$Status, [object]$PassInterpretation, [bool]$StrictMode)
    $s = $Status.ToLowerInvariant()
    if (-not $PassInterpretation) {
        if ($StrictMode) { return ($s -eq 'ok') }
        return ($s -in @('ok', 'warn'))
    }
    $aliases = @($PassInterpretation.nonPassStatusAliases | ForEach-Object { [string]$_ })
    foreach ($a in $aliases) {
        if ($s -eq $a.ToLowerInvariant()) { return $false }
    }
    foreach ($x in @($PassInterpretation.statusesNeverEquivalentToPassed | ForEach-Object { [string]$_ })) {
        if ($s -eq $x.ToLowerInvariant()) { return $false }
    }
    if ($PassInterpretation.onlyStatusOkIsPass) {
        return ($s -eq 'ok')
    }
    return $true
}

$gatePath = Join-Path $RepoRoot (Join-Path 'quality-gates' "$Gate.json")
if (-not (Test-Path -LiteralPath $gatePath)) {
    throw "Quality gate file missing: quality-gates/$Gate.json"
}

$doc = Get-Content -LiteralPath $gatePath -Raw -Encoding utf8 | ConvertFrom-Json
$passPi = $null
if ($doc.PSObject.Properties.Name -contains 'passInterpretation') {
    $passPi = $doc.passInterpretation
}

$blocking = @($doc.blockingWarnings | ForEach-Object { [string]$_ })
$allowed = @($doc.allowedWarnings | ForEach-Object { [string]$_ })

foreach ($v in @($doc.requiredValidators)) {
    $vid = [string]$v.id
    $rel = [string]$v.script
    $p = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
    $argList = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @($v.arguments | ForEach-Object { [string]$_ })) {
        if ($a -match '[`;&|]' -or $a -match '\.\.') { throw "unsafe argument in gate $Gate validator $vid" }
        [void]$argList.Add($a)
    }
    $emitJson = ($v.PSObject.Properties.Name -contains 'emitJson') -and [bool]$v.emitJson
    if ($emitJson -and ($argList -notcontains '-Json')) { [void]$argList.Add('-Json') }

    if ($Strict) {
        if ($Gate -eq 'skills' -and $vid -in @('verify-skills-manifest', 'verify-skills-drift')) {
            [void]$argList.Add('-Strict')
        }
        if ($Gate -eq 'adapters' -and $vid -eq 'verify-agent-adapter-drift') {
            [void]$argList.Add('-FailOnDrift')
        }
    }

    $lines = @(& pwsh -NoProfile -WorkingDirectory $RepoRoot -File $p @($argList.ToArray()) 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $outcome = Get-OutcomeFromRun -Lines $lines -ExitCode $code -EmitJson:$emitJson
    $st = [string]$outcome.status

    if (-not (Test-GateStatusPass -Status $st -PassInterpretation $passPi -StrictMode:$Strict)) {
        [void]$failures.Add("$vid status=$st (gate policy)")
    }

    foreach ($w in @($outcome.warnings)) {
        if ([string]::IsNullOrWhiteSpace($w)) { continue }
        $isBlock = ($blocking -contains '*')
        $okWarn = (Test-WarningAllowed -Text $w -Allowed:$allowed)
        if ($isBlock -and -not $okWarn) {
            [void]$failures.Add("$vid warning blocked: $w")
        }
        elseif (-not $okWarn -and $Strict) {
            [void]$warnings.Add("$vid warning: $w")
        }
    }

    [void]$findings.Add([ordered]@{
            validator = $vid
            exitCode  = $code
            status    = $st
        })
    [void]$checks.Add([ordered]@{ name = $vid; status = $(if ($st -eq 'ok') { 'ok' } else { 'fail' }); detail = $rel })
}

[void]$findings.Insert(0, [ordered]@{ gate = [string]$doc.id; domain = $Gate })

$sw.Stop()
$agg = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool "evaluate-quality-gate-$Gate" -Status $agg -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "evaluate-quality-gate [$Gate]: $($env.status)"
    foreach ($f in $findings) {
        if ($f.validator) {
            Write-Host "  $($f.validator) exit=$($f.exitCode) status=$($f.status)"
        }
    }
}

if ($failures.Count -gt 0) { exit 1 }
if ($doc.id -in @('gate.release', 'gate.strict') -and $agg -ne 'ok') { exit 1 }
if ($Strict -and $agg -eq 'warn') { exit 1 }
exit 0
