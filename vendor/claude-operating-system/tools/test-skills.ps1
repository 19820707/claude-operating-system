# test-skills.ps1 — Lightweight skill regression tests (manifest contracts only; no LLM)
#   pwsh ./tools/test-skills.ps1 [-Json]
# Cases: tests/skills/cases/*.json — schema: schemas/skill-test-case.schema.json

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tools/lib/safe-output.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation-envelope.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$warnings = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

function Fail {
    param([string]$Message)
    [void]$script:failures.Add($Message)
}

function Test-AnyLineContains {
    param(
        [string]$Needle,
        [string[]]$HaystackLines
    )
    $n = $Needle.ToLowerInvariant()
    foreach ($line in $HaystackLines) {
        if ([string]$line -and $line.ToLowerInvariant().Contains($n)) { return $true }
    }
    return $false
}

function Test-ApprovalCovered {
    param(
        [string]$Expected,
        [string]$RouteRequiredApproval,
        [string[]]$SkillRequiresApprovalFor
    )
    if ($Expected -ieq $RouteRequiredApproval) { return $true }
    foreach ($s in $SkillRequiresApprovalFor) {
        if ($Expected -ieq [string]$s) { return $true }
    }
    return $false
}

try {
    $skillsPath = Join-Path $RepoRoot 'skills-manifest.json'
    $capPath = Join-Path $RepoRoot 'capability-manifest.json'
    $casesDir = Join-Path $RepoRoot 'tests/skills/cases'
    if (-not (Test-Path -LiteralPath $skillsPath)) { throw 'missing skills-manifest.json' }
    if (-not (Test-Path -LiteralPath $capPath)) { throw 'missing capability-manifest.json' }
    if (-not (Test-Path -LiteralPath $casesDir)) { throw 'missing tests/skills/cases' }

    $sm = Get-Content -LiteralPath $skillsPath -Raw | ConvertFrom-Json
    $cm = Get-Content -LiteralPath $capPath -Raw | ConvertFrom-Json

    $skillById = @{}
    foreach ($sk in @($sm.skills)) { $skillById[[string]$sk.id] = $sk }

    $routeById = @{}
    foreach ($rt in @($cm.routes)) { $routeById[[string]$rt.id] = $rt }

    $caseFiles = @(Get-ChildItem -LiteralPath $casesDir -Filter '*.json' -File | Sort-Object Name)
    if ($caseFiles.Count -eq 0) { throw 'no JSON test cases under tests/skills/cases' }

    $caseIds = @{}

    foreach ($file in $caseFiles) {
        $rel = 'tests/skills/cases/' + $file.Name
        $tc = $null
        try {
            $tc = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        }
        catch {
            Fail "$rel invalid JSON: $($_.Exception.Message)"
            continue
        }

        $cid = [string]$tc.id
        if ([string]::IsNullOrWhiteSpace($cid)) {
            Fail "$rel missing id"
            continue
        }
        if ($caseIds.ContainsKey($cid)) { Fail "duplicate test case id: $cid" }
        $caseIds[$cid] = $true

        $skillId = [string]$tc.skillId
        $routeId = [string]$tc.routeId
        if (-not $skillById.ContainsKey($skillId)) {
            Fail "[$cid] unknown skillId '$skillId' (skills-manifest)"
            continue
        }
        if (-not $routeById.ContainsKey($routeId)) {
            Fail "[$cid] unknown routeId '$routeId' (capability-manifest)"
            continue
        }

        $skill = $skillById[$skillId]
        $route = $routeById[$routeId]
        $relevant = @($route.relevantSkills | ForEach-Object { [string]$_ })
        if ($relevant -notcontains $skillId) {
            Fail "[$cid] skill '$skillId' not in route '$routeId' relevantSkills: $($relevant -join ', ')"
        }

        $expMode = [string]$tc.expectedOperatingMode
        if ($route.operatingMode -ne $expMode) {
            Fail "[$cid] expectedOperatingMode '$expMode' but route has '$($route.operatingMode)'"
        }

        $skillApprovals = @($skill.requiresApprovalFor | ForEach-Object { [string]$_ })
        $routeTier = [string]$route.requiredApproval
        foreach ($expAp in @($tc.expectedRequiredApprovals | ForEach-Object { [string]$_ })) {
            if (-not (Test-ApprovalCovered -Expected $expAp -RouteRequiredApproval $routeTier -SkillRequiresApprovalFor $skillApprovals)) {
                Fail "[$cid] expectedRequiredApprovals '$expAp' not matched by route.requiredApproval='$routeTier' nor skill.requiresApprovalFor"
            }
        }

        $valLines = @($route.validators | ForEach-Object { [string]$_ })
        foreach ($needle in @($tc.expectedValidators | ForEach-Object { [string]$_ })) {
            if (-not (Test-AnyLineContains -Needle $needle -HaystackLines $valLines)) {
                Fail "[$cid] expectedValidators substring not found on route validators: '$needle'"
            }
        }

        $forbiddenLines = @($route.forbiddenShortcuts | ForEach-Object { [string]$_ })
        foreach ($needle in @($tc.forbiddenActions | ForEach-Object { [string]$_ })) {
            if (-not (Test-AnyLineContains -Needle $needle -HaystackLines $forbiddenLines)) {
                Fail "[$cid] forbiddenActions substring not found in route.forbiddenShortcuts: '$needle'"
            }
        }

        $refusalHaystack = @(
            @($route.forbiddenShortcuts | ForEach-Object { [string]$_ })
            @($route.expectedEvidence | ForEach-Object { [string]$_ })
        )
        foreach ($needle in @($tc.expectedRefusalOrAbortConditions | ForEach-Object { [string]$_ })) {
            if (-not (Test-AnyLineContains -Needle $needle -HaystackLines $refusalHaystack)) {
                Fail "[$cid] expectedRefusalOrAbortConditions substring not in forbiddenShortcuts or expectedEvidence: '$needle'"
            }
        }

        if ($tc.PSObject.Properties.Name -contains 'expectedSkillRiskLevel') {
            $ers = [string]$tc.expectedSkillRiskLevel
            if ($skill.riskLevel -ne $ers) {
                Fail "[$cid] expectedSkillRiskLevel '$ers' but skill has '$($skill.riskLevel)'"
            }
        }
        if ($tc.PSObject.Properties.Name -contains 'expectedRouteRiskLevel') {
            $errl = [string]$tc.expectedRouteRiskLevel
            if ($route.riskLevel -ne $errl) {
                Fail "[$cid] expectedRouteRiskLevel '$errl' but route has '$($route.riskLevel)'"
            }
        }

        [void]$findings.Add([ordered]@{
                case   = $cid
                file   = $rel
                skill  = $skillId
                route  = $routeId
                status = 'ok'
            })
    }

    [void]$checks.Add([ordered]@{
            name   = 'skill-contract-cases'
            status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' })
            detail = "$($caseFiles.Count) case(s) vs skills-manifest + capability-manifest"
        })
}
catch {
    Fail (Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400)
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'test-skills' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 14 -Compress | Write-Output
}
else {
    Write-Host "test-skills: $($env.status) ($($findings.Count) case(s))"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
