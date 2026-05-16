# epistemic-tracker.ps1 — Epistemic state: KNOWN/INFERRED/ASSUMED/UNKNOWN fact management
# A system that knows what it doesn't know is fundamentally more reliable.
# Maintains .claude/epistemic-state.json with confidence decay and assumption debt scoring.
#   pwsh ./tools/epistemic-tracker.ps1 -Mode update
#   pwsh ./tools/epistemic-tracker.ps1 -Mode assert -Fact "exit_hygiene" -FactStatus KNOWN -Evidence "commit abc1234" -Confidence 1.0
#   pwsh ./tools/epistemic-tracker.ps1 -Mode gate -DependsOn "exit_hygiene","auth_boundary"
#   pwsh ./tools/epistemic-tracker.ps1 -Mode debt-report
#   pwsh ./tools/epistemic-tracker.ps1 -Mode auto-discover
#   pwsh ./tools/epistemic-tracker.ps1 -Json

param(
    [ValidateSet('update','assert','gate','debt-report','auto-discover')]
    [string]$Mode = 'debt-report',
    [string]$Fact = '',
    [ValidateSet('','KNOWN','INFERRED','ASSUMED','UNKNOWN')]
    [string]$FactStatus = '',
    [string]$Evidence = '',
    [double]$Confidence = 0.0,
    [string[]]$DependsOn = @(),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib/safe-output.ps1')
. (Join-Path $PSScriptRoot 'lib/validation-envelope.ps1')

$sw       = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

$StatePath = Join-Path $RepoRoot '.claude/epistemic-state.json'

# ── State I/O ─────────────────────────────────────────────────────────────────

function Get-EpistemicState {
    if (Test-Path -LiteralPath $StatePath) {
        try { return Get-Content -LiteralPath $StatePath -Raw -Encoding utf8 | ConvertFrom-Json } catch { }
    }
    return [PSCustomObject]@{
        facts           = [PSCustomObject]@{}
        unknowns        = @()
        assumption_debt = 0
    }
}

function Save-EpistemicState {
    param([object]$State)
    $json = $State | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($StatePath, ($json -replace "`r`n", "`n"), [System.Text.Encoding]::UTF8)
}

function Apply-ConfidenceDecay {
    param([double]$Conf, [double]$Rate, [string]$VerifiedAt)
    try {
        $last = [datetime]::ParseExact($VerifiedAt, 'yyyy-MM-dd', $null)
        $days = ([datetime]::Today - $last).TotalDays
        return [Math]::Max(0.0, [Math]::Round($Conf * (1 - $Rate * $days), 4))
    } catch { return $Conf }
}

function Compute-Debt {
    param([object]$State)
    $debt = 0
    foreach ($kv in @($State.facts.PSObject.Properties)) {
        $f = $kv.Value
        if ($f.status -eq 'ASSUMED' -and [double]$f.confidence -lt 0.5) { $debt++ }
        if ($f.status -eq 'STALE')                                        { $debt++ }
    }
    foreach ($u in @($State.unknowns)) {
        if ($u.priority -eq 'HIGH') { $debt += 2 } else { $debt++ }
    }
    return [Math]::Min(10, $debt)
}

# ── MODE: update ──────────────────────────────────────────────────────────────

if ($Mode -eq 'update') {
    $state   = Get-EpistemicState
    $decayed = 0

    foreach ($kv in @($state.facts.PSObject.Properties)) {
        $f    = $kv.Value
        $rate = if ($f.decay_rate) { [double]$f.decay_rate } else { 0.02 }
        $prev = [double]$f.confidence
        $new  = Apply-ConfidenceDecay -Conf $prev -Rate $rate -VerifiedAt ([string]$f.verified_at)
        if ($new -lt $prev) { $decayed++ }
        $f.confidence = $new
        if ($new -lt 0.3 -and $f.status -notin @('UNKNOWN','STALE')) { $f.status = 'STALE' }
    }

    $debt = Compute-Debt -State $state
    $state | Add-Member -MemberType NoteProperty -Name 'assumption_debt' -Value $debt -Force
    Save-EpistemicState -State $state

    [void]$checks.Add([ordered]@{ name = 'update'; status = 'ok'; detail = "decayed=${decayed} debt=${debt}" })
    $env = New-OsValidatorEnvelope -Tool 'epistemic-tracker' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) `
        -Findings @([ordered]@{ facts_decayed = $decayed; assumption_debt = $debt })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else { Write-Host "epistemic-tracker | update | decayed=${decayed} debt=${debt}" }
    exit 0
}

# ── MODE: assert ──────────────────────────────────────────────────────────────

if ($Mode -eq 'assert') {
    if (-not $Fact -or -not $FactStatus) {
        [void]$failures.Add('-Fact and -FactStatus required for assert mode')
        $env = New-OsValidatorEnvelope -Tool 'epistemic-tracker' -Status 'fail' -DurationMs ([int]$sw.ElapsedMilliseconds) -Failures @($failures)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host 'epistemic-tracker | assert | error: -Fact and -FactStatus required' }
        exit 0
    }

    if ($FactStatus -eq 'KNOWN' -and $Evidence -notmatch '[0-9a-f]{7,}|pwsh|bash|verify') {
        [void]$warnings.Add("KNOWN status should reference a commit hash or verification command in -Evidence")
    }

    $conf = if ($Confidence -gt 0) { $Confidence } else {
        switch ($FactStatus) { 'KNOWN' { 1.0 } 'INFERRED' { 0.7 } 'ASSUMED' { 0.5 } default { 0.0 } }
    }
    $rate = switch ($FactStatus) { 'KNOWN' { 0.01 } 'INFERRED' { 0.05 } 'ASSUMED' { 0.08 } default { 0.0 } }

    $state   = Get-EpistemicState
    $newFact = [PSCustomObject]@{
        status               = $FactStatus
        evidence             = $Evidence
        confidence           = $conf
        verified_at          = (Get-Date).ToString('yyyy-MM-dd')
        verification_command = $null
        decay_rate           = $rate
    }
    $state.facts | Add-Member -MemberType NoteProperty -Name $Fact -Value $newFact -Force
    Save-EpistemicState -State $state

    [void]$checks.Add([ordered]@{ name = 'assert'; status = 'ok'; detail = "${Fact} status=${FactStatus} confidence=${conf}" })
    $env = New-OsValidatorEnvelope -Tool 'epistemic-tracker' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Findings @([ordered]@{ fact = $Fact; status = $FactStatus; confidence = $conf })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else { Write-Host "epistemic-tracker | assert | ${Fact} status=${FactStatus} confidence=${conf}" }
    exit 0
}

# ── MODE: gate ────────────────────────────────────────────────────────────────

if ($Mode -eq 'gate') {
    $state      = Get-EpistemicState
    $gateResult = 'GATE PASSED'
    $issues     = [System.Collections.Generic.List[string]]::new()
    $hardFail   = $false
    $softFail   = $false

    foreach ($slug in $DependsOn) {
        $prop = $state.facts.PSObject.Properties[$slug]
        if (-not $prop) {
            $unk = @($state.unknowns | Where-Object { $_.id -eq $slug -or $_.question -match [regex]::Escape($slug) }) | Select-Object -First 1
            if ($unk -and $unk.priority -eq 'HIGH') {
                $hardFail = $true
                [void]$issues.Add("HARD: ${slug} is UNKNOWN (HIGH priority)")
            } else {
                $softFail = $true
                [void]$issues.Add("SOFT: ${slug} not in epistemic state")
            }
            continue
        }

        $f    = $prop.Value
        $conf = [double]$f.confidence
        $st   = [string]$f.status

        if ($st -eq 'ASSUMED' -and $conf -lt 0.3) {
            $hardFail = $true; [void]$issues.Add("HARD: ${slug} is ASSUMED confidence=${conf} (< 0.3)")
        } elseif ($st -eq 'ASSUMED' -and $conf -lt 0.5) {
            $softFail = $true; [void]$issues.Add("SOFT: ${slug} is ASSUMED confidence=${conf} (< 0.5)")
        } elseif ($st -eq 'INFERRED' -and $conf -lt 0.4) {
            $softFail = $true; [void]$issues.Add("SOFT: ${slug} is INFERRED confidence=${conf} (< 0.4)")
        } elseif ($st -eq 'UNKNOWN') {
            $hardFail = $true; [void]$issues.Add("HARD: ${slug} is UNKNOWN")
        } elseif ($st -eq 'STALE') {
            $softFail = $true; [void]$issues.Add("SOFT: ${slug} is STALE confidence=${conf}")
        }
    }

    if ($hardFail)     { $gateResult = 'GATE HARD FAIL' }
    elseif ($softFail) { $gateResult = 'GATE SOFT FAIL' }

    $envStatus = if ($hardFail) { 'fail' } elseif ($softFail) { 'warn' } else { 'ok' }
    [void]$checks.Add([ordered]@{ name = 'gate'; status = $envStatus; detail = $gateResult })
    $env = New-OsValidatorEnvelope -Tool 'epistemic-tracker' -Status $envStatus -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
        -Findings @([ordered]@{ gate_status = $gateResult; issues = @($issues); depends_on_count = $DependsOn.Count })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else {
        Write-Host "epistemic-tracker | gate | ${gateResult}"
        foreach ($issue in $issues) { Write-Host "  ${issue}" }
    }

    if ($hardFail) { exit 1 }
    exit 0
}

# ── MODE: debt-report ─────────────────────────────────────────────────────────

if ($Mode -eq 'debt-report') {
    $state    = Get-EpistemicState
    $debt     = Compute-Debt -State $state
    $assumed  = @($state.facts.PSObject.Properties | Where-Object { $_.Value.status -in @('ASSUMED','STALE') } | Sort-Object { [double]$_.Value.confidence })
    $unknowns = @($state.unknowns | Sort-Object { if ($_.priority -eq 'HIGH') { 0 } else { 1 } })

    $debtLabel = if ($debt -ge 7) {
        'EPISTEMIC DEBT HIGH — system operating with significant uncertainty'
    } elseif ($debt -ge 4) {
        'EPISTEMIC DEBT MODERATE — review assumptions before critical changes'
    } else {
        'EPISTEMIC DEBT LOW — system knowledge is solid'
    }

    $st = if ($debt -ge 7) { 'warn' } else { 'ok' }
    if ($debt -ge 7) { [void]$warnings.Add($debtLabel) }

    [void]$checks.Add([ordered]@{ name = 'debt-report'; status = $st; detail = "debt=${debt}/10 assumed=$($assumed.Count) unknowns=$($unknowns.Count)" })
    $env = New-OsValidatorEnvelope -Tool 'epistemic-tracker' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) `
        -Findings @([ordered]@{
            assumption_debt = $debt
            debt_label      = $debtLabel
            assumed_stale   = $assumed.Count
            unknowns        = $unknowns.Count
            top_issues      = @($assumed | Select-Object -First 5 | ForEach-Object {
                [ordered]@{ fact = $_.Name; status = $_.Value.status; confidence = $_.Value.confidence }
            })
            top_unknowns    = @($unknowns | Select-Object -First 3 | ForEach-Object {
                [ordered]@{ id = $_.id; priority = $_.priority; question = $_.question }
            })
        })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else {
        Write-Host "epistemic-tracker | debt=${debt}/10 | ${debtLabel}"
        if ($assumed.Count -gt 0) {
            Write-Host '  Assumed/Stale:'
            foreach ($f in ($assumed | Select-Object -First 5)) {
                Write-Host "    $($f.Name): $($f.Value.status) confidence=$($f.Value.confidence)"
            }
        }
        if ($unknowns.Count -gt 0) {
            Write-Host '  Unknowns:'
            foreach ($u in ($unknowns | Select-Object -First 3)) {
                Write-Host "    [$($u.priority)] $($u.id): $($u.question)"
            }
        }
    }
    exit 0
}

# ── MODE: auto-discover ───────────────────────────────────────────────────────

if ($Mode -eq 'auto-discover') {
    Push-Location $RepoRoot
    try {
        $state       = Get-EpistemicState
        $newUnknowns = [System.Collections.Generic.List[object]]::new()
        $suggestions = [System.Collections.Generic.List[string]]::new()
        $today       = (Get-Date).ToString('yyyy-MM-dd')
        $nextUnkId   = [int]((@($state.unknowns | ForEach-Object { $_.id -replace 'UNK-', '' } | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ } | Select-Object -Last 1) + 0)) + 1

        # Check working tree PS1 files for missing epistemic facts
        $wtFiles = @(& git diff --name-only HEAD 2>$null) + @(& git ls-files --others --exclude-standard 2>$null)

        foreach ($f in ($wtFiles | Where-Object { $_ -match '\.ps1$' } | Select-Object -Unique)) {
            $slug      = ($f -replace '[/\\.]', '_')
            $exitFact  = "${slug}_exits_zero_on_success"
            $existProp = $state.facts.PSObject.Properties[$exitFact]

            if (-not $existProp) {
                $fname = [System.IO.Path]::GetFileName($f)
                $verifyCmd = "pwsh ./tools/verify-exit-codes.ps1 -Json 2>`$null | ConvertFrom-Json | Select-Object -ExpandProperty findings | Where-Object { `$_.file -match '${fname}' }"
                $newUnknowns.Add([PSCustomObject]@{
                    id                   = "UNK-$('{0:D3}' -f $nextUnkId++)"
                    question             = "Does ${f} have explicit exit 0 on all success paths? (INV-011)"
                    blocking             = @("any commit touching ${f}")
                    priority             = 'MEDIUM'
                    raised_at            = $today
                    verification_command = $verifyCmd
                })
            } elseif ([double]$existProp.Value.confidence -lt 0.5) {
                [void]$suggestions.Add("${exitFact} (confidence=$([double]$existProp.Value.confidence)) — re-verify: pwsh ./tools/verify-exit-codes.ps1")
            }
        }

        # Merge without duplicates
        $existingUnks = [System.Collections.Generic.List[object]]::new()
        foreach ($u in @($state.unknowns)) { [void]$existingUnks.Add($u) }
        foreach ($u in $newUnknowns) {
            $dup = @($existingUnks | Where-Object { $_.question -eq $u.question }).Count
            if ($dup -eq 0) { [void]$existingUnks.Add($u) }
        }
        $state.unknowns = @($existingUnks)
        Save-EpistemicState -State $state

        [void]$checks.Add([ordered]@{ name = 'auto-discover'; status = 'ok'; detail = "new_unknowns=$($newUnknowns.Count) suggestions=$($suggestions.Count)" })
        $env = New-OsValidatorEnvelope -Tool 'epistemic-tracker' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Checks @($checks) -Findings @([ordered]@{ new_unknowns = $newUnknowns.Count; suggestions = @($suggestions) })
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else {
            Write-Host "epistemic-tracker | auto-discover | new_unknowns=$($newUnknowns.Count)"
            foreach ($s in $suggestions) { Write-Host "  SUGGEST: ${s}" }
        }
    } finally { Pop-Location }
    exit 0
}

exit 0
