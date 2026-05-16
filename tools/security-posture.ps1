# security-posture.ps1 — Consolidated security posture score (0-100, grade A-F)
# Aggregates: secrets, scope control, security policy, token economy, settings hygiene.
# CISO-level view. Run standalone or wired into strict validation.
#   pwsh ./tools/security-posture.ps1
#   pwsh ./tools/security-posture.ps1 -Json
#   pwsh ./tools/security-posture.ps1 -Strict   # fail on grade < B

param(
    [switch]$Strict,
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
$findings = [System.Collections.Generic.List[object]]::new()

$score   = 100   # Start at 100, deduct for failures
$maxDeductions = 0

function Invoke-Verifier {
    param([string]$Name, [string]$Tool, [string[]]$Args, [int]$MaxDeduction, [string]$Description)
    $script:maxDeductions += $MaxDeduction
    $p = Join-Path $RepoRoot "tools/$Tool"
    if (-not (Test-Path -LiteralPath $p)) {
        [void]$script:warnings.Add("${Name}: verifier $Tool not found")
        [void]$script:checks.Add([ordered]@{ name = $Name; status = 'warn'; detail = 'verifier missing' })
        [void]$script:findings.Add([ordered]@{ check = $Name; status = 'SKIP'; deduction = 0; description = $Description })
        return
    }
    try {
        $raw = @(& pwsh -NoProfile -File $p @Args 2>$null)
        $exit = $LASTEXITCODE
        $jsonLine = $raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
        $st = 'ok'
        if ($jsonLine) {
            try { $st = [string](($jsonLine | ConvertFrom-Json).status) } catch { }
        }
        if ($exit -ne 0 -or $st -eq 'fail') {
            $script:score -= $MaxDeduction
            [void]$script:checks.Add([ordered]@{ name = $Name; status = 'fail'; detail = "exit=$exit status=$st" })
            [void]$script:findings.Add([ordered]@{ check = $Name; status = 'FAIL'; deduction = $MaxDeduction; description = $Description })
            [void]$script:warnings.Add("$Name failed — deducting $MaxDeduction points")
        } elseif ($st -in @('warn','degraded')) {
            $partial = [Math]::Floor($MaxDeduction / 2)
            $script:score -= $partial
            [void]$script:checks.Add([ordered]@{ name = $Name; status = 'warn'; detail = "status=$st partial deduction" })
            [void]$script:findings.Add([ordered]@{ check = $Name; status = 'WARN'; deduction = $partial; description = $Description })
        } else {
            [void]$script:checks.Add([ordered]@{ name = $Name; status = 'ok'; detail = 'passed' })
            [void]$script:findings.Add([ordered]@{ check = $Name; status = 'PASS'; deduction = 0; description = $Description })
        }
    } catch {
        $script:score -= $MaxDeduction
        [void]$script:warnings.Add("${Name}: invocation error — $($_.Exception.Message)")
        [void]$script:checks.Add([ordered]@{ name = $Name; status = 'fail'; detail = $_.Exception.Message })
        [void]$script:findings.Add([ordered]@{ check = $Name; status = 'ERROR'; deduction = $MaxDeduction; description = $Description })
    }
}

# ── Verifier-backed checks (30 pts each × 3 = 90 total) ──────────────────────

Invoke-Verifier -Name 'no-secrets'         -Tool 'verify-no-secrets.ps1'         -Args @('-Json')       -MaxDeduction 30 `
    -Description 'Secret/credential patterns in tracked files'

Invoke-Verifier -Name 'scope-control'      -Tool 'verify-claudeignore.ps1'        -Args @('-Json')       -MaxDeduction 25 `
    -Description 'Claudeignore scope-control defaults — prevents cross-project contamination'

Invoke-Verifier -Name 'security-policy'    -Tool 'verify-security-policy.ps1'     -Args @('-Json')       -MaxDeduction 20 `
    -Description 'Security threat model and no-false-green contracts present'

Invoke-Verifier -Name 'token-economy'      -Tool 'verify-token-economy-policy.ps1' -Args @('-Json')      -MaxDeduction 10 `
    -Description 'Token budget discipline — prevents unbounded context consumption'

# ── Static analysis: settings.json dangerous allows (15 pts) ─────────────────

$settingsScore = 15
$settingsPath  = Join-Path $RepoRoot '.claude/settings.json'
if (-not (Test-Path -LiteralPath $settingsPath)) {
    [void]$warnings.Add('settings.json not found — cannot audit permission allows')
    [void]$checks.Add([ordered]@{ name = 'settings-hygiene'; status = 'warn'; detail = 'missing settings.json' })
    [void]$findings.Add([ordered]@{ check = 'settings-hygiene'; status = 'SKIP'; deduction = 0; description = 'Permission allow-list audit' })
} else {
    try {
        $s = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $allows   = @($s.permissions.allow | ForEach-Object { [string]$_ })
        $denies   = @($s.permissions.deny  | ForEach-Object { [string]$_ })
        $dangPats = @('Bash(rm *)', 'Bash(curl * | bash)', 'Bash(wget * | sh)', 'Bash(*--force*)', 'Bash(*eval*)')
        $dangFound = [System.Collections.Generic.List[string]]::new()
        foreach ($a in $allows) {
            foreach ($d in $dangPats) {
                if ($a -like $d) { [void]$dangFound.Add($a) }
            }
        }
        # Check critical deny patterns are present
        $critDenies = @('git push --force', 'git push -f', 'git push --mirror')
        $missingDenies = $critDenies | Where-Object { $dn = $_; -not ($denies | Where-Object { $_ -match [regex]::Escape($dn) }) }

        if ($dangFound.Count -gt 0) {
            $deduction = [Math]::Min($settingsScore, $dangFound.Count * 5)
            $score -= $deduction
            [void]$findings.Add([ordered]@{ check = 'settings-hygiene'; status = 'FAIL'; deduction = $deduction; description = "Dangerous allow patterns: $($dangFound -join ', ')" })
            [void]$checks.Add([ordered]@{ name = 'settings-hygiene'; status = 'fail'; detail = "dangerous allows: $($dangFound -join '; ')" })
        } elseif ($missingDenies.Count -gt 0) {
            $score -= 5
            [void]$findings.Add([ordered]@{ check = 'settings-hygiene'; status = 'WARN'; deduction = 5; description = "Missing deny rules: $($missingDenies -join ', ')" })
            [void]$checks.Add([ordered]@{ name = 'settings-hygiene'; status = 'warn'; detail = "missing deny: $($missingDenies -join '; ')" })
        } else {
            [void]$findings.Add([ordered]@{ check = 'settings-hygiene'; status = 'PASS'; deduction = 0; description = 'No dangerous allows; critical denies present' })
            [void]$checks.Add([ordered]@{ name = 'settings-hygiene'; status = 'ok'; detail = "$($allows.Count) allows, $($denies.Count) denies — clean" })
        }
    } catch {
        [void]$warnings.Add("settings.json parse error: $($_.Exception.Message)")
        [void]$checks.Add([ordered]@{ name = 'settings-hygiene'; status = 'warn'; detail = 'parse error' })
        [void]$findings.Add([ordered]@{ check = 'settings-hygiene'; status = 'SKIP'; deduction = 0; description = 'Permission allow-list audit' })
    }
}

# ── Clamp and grade ───────────────────────────────────────────────────────────

$score = [Math]::Max(0, [Math]::Min(100, $score))
$grade = switch ($true) {
    ($score -ge 95) { 'A' }
    ($score -ge 85) { 'B' }
    ($score -ge 70) { 'C' }
    ($score -ge 55) { 'D' }
    default         { 'F' }
}

$interpretation = switch ($grade) {
    'A' { 'Excellent security posture — all critical controls present and verified' }
    'B' { 'Good posture — minor gaps detected; review warnings' }
    'C' { 'Moderate risk — multiple controls failing; prioritise remediation' }
    'D' { 'High risk — significant security gaps; block production use until resolved' }
    'F' { 'Critical — fundamental security controls missing; system must not be used in production' }
}

if ($Strict -and $grade -in @('C','D','F')) {
    [void]$failures.Add("Security posture grade $grade ($score/100) below acceptable threshold — $interpretation")
}
if ($grade -in @('D','F') -and -not $Strict) {
    [void]$warnings.Add("Security posture grade $grade ($score/100) — $interpretation")
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0 -or $grade -in @('C','D')) { 'warn' } else { 'ok' }

$env = New-OsValidatorEnvelope -Tool 'security-posture' -Status $st `
    -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) `
    -Findings @(@([ordered]@{
        score          = $score
        grade          = $grade
        interpretation = $interpretation
        checks         = @($findings)
    }))

if ($Json) {
    $env | ConvertTo-Json -Depth 10 -Compress | Write-Output
} else {
    Write-Host "security-posture | score=$score/100 | grade=$grade | $interpretation"
    Write-Host ''
    foreach ($f in $findings) {
        $icon = switch ($f.status) { 'PASS'{'OK'}; 'FAIL'{'FAIL'}; 'WARN'{'WARN'}; default{'SKIP'} }
        $ded  = if ([int]$f.deduction -gt 0) { " (-$($f.deduction))" } else { '' }
        Write-Host "  [$icon]$ded $($f.description)"
    }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
