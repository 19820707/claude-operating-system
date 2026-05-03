# verify-doc-contract-consistency.ps1 — README / manifests / entrypoints coherence (no false-green wording)
#   pwsh ./tools/verify-doc-contract-consistency.ps1 [-Json]

[CmdletBinding()]
param(
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

function Add-Finding {
    param([string]$File, [string]$Expected, [string]$Actual, [string]$Severity)
    $script:findings.Add([ordered]@{
            file     = $File
            expected = $Expected
            actual   = $Actual
            severity = $Severity
        })
}

try {
    $omPath = Join-Path $RepoRoot 'os-manifest.json'
    $om = Get-Content -LiteralPath $omPath -Raw | ConvertFrom-Json
    foreach ($p in $om.entrypoints.PSObject.Properties) {
        $rel = [string]$p.Value
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            [void]$failures.Add("os-manifest entrypoints.$($p.Name) missing file: $rel")
            Add-Finding -File 'os-manifest.json' -Expected $rel -Actual 'missing' -Severity 'fail'
        }
    }

    if ($null -ne $om.manifests) {
        foreach ($mp in $om.manifests.PSObject.Properties) {
            $relM = [string]$mp.Value
            $fullM = Join-Path $RepoRoot $relM
            if (-not (Test-Path -LiteralPath $fullM)) {
                [void]$failures.Add("os-manifest.manifests.$($mp.Name) missing path: $relM")
                Add-Finding -File 'os-manifest.json' -Expected $relM -Actual 'missing' -Severity 'fail'
            }
        }
    }

    $schemaPairs = @(
        @{ j = 'os-manifest.json'; s = 'schemas/os-manifest.schema.json' }
        @{ j = 'bootstrap-manifest.json'; s = 'schemas/bootstrap-manifest.schema.json' }
        @{ j = 'docs-index.json'; s = 'schemas/docs-index.schema.json' }
        @{ j = 'os-capabilities.json'; s = 'schemas/os-capabilities.schema.json' }
        @{ j = 'capability-manifest.json'; s = 'schemas/capability-manifest.schema.json' }
        @{ j = 'deprecation-manifest.json'; s = 'schemas/deprecation-manifest.schema.json' }
        @{ j = 'quality-gates/docs.json'; s = 'schemas/quality-gate.schema.json' }
        @{ j = 'quality-gates/skills.json'; s = 'schemas/quality-gate.schema.json' }
        @{ j = 'quality-gates/release.json'; s = 'schemas/quality-gate.schema.json' }
        @{ j = 'quality-gates/bootstrap.json'; s = 'schemas/quality-gate.schema.json' }
        @{ j = 'quality-gates/adapters.json'; s = 'schemas/quality-gate.schema.json' }
        @{ j = 'quality-gates/security.json'; s = 'schemas/quality-gate.schema.json' }
        @{ j = 'workflow-manifest.json'; s = 'schemas/workflow-manifest.schema.json' }
        @{ j = 'agent-adapters-manifest.json'; s = 'schemas/agent-adapters.schema.json' }
        @{ j = 'runtime-budget.json'; s = 'schemas/runtime-budget.schema.json' }
        @{ j = 'policies/autonomy-policy.json'; s = 'schemas/autonomy-policy.schema.json' }
        @{ j = 'context-budget.json'; s = 'schemas/context-budget.schema.json' }
        @{ j = 'script-manifest.json'; s = 'schemas/script-manifest.schema.json' }
        @{ j = 'skills-manifest.json'; s = 'schemas/skills-manifest.schema.json' }
        @{ j = 'playbook-manifest.json'; s = 'schemas/playbook-manifest.schema.json' }
        @{ j = 'recipe-manifest.json'; s = 'schemas/recipe-manifest.schema.json' }
        @{ j = 'upgrade-manifest.json'; s = 'schemas/upgrade-manifest.schema.json' }
    )
    foreach ($row in $schemaPairs) {
        $jPath = Join-Path $RepoRoot $row.j
        $sPath = Join-Path $RepoRoot $row.s
        if (-not (Test-Path -LiteralPath $jPath)) {
            [void]$failures.Add("contract JSON missing: $($row.j)")
            Add-Finding -File 'doc-contract' -Expected $row.j -Actual 'missing' -Severity 'fail'
            continue
        }
        if (-not (Test-Path -LiteralPath $sPath)) {
            [void]$failures.Add("schema missing for $($row.j): $($row.s)")
            Add-Finding -File 'doc-contract' -Expected $row.s -Actual 'missing' -Severity 'fail'
        }
    }

    $rpPath = Join-Path $RepoRoot 'runtime-profiles.json'
    $rp = Get-Content -LiteralPath $rpPath -Raw | ConvertFrom-Json
    $rtSrc = Get-Content -LiteralPath (Join-Path $RepoRoot 'tools/os-runtime.ps1') -Raw
    foreach ($prof in @($rp.profiles)) {
        foreach ($cmd in @($prof.commands)) {
            $c = [string]$cmd
            if ($c -eq 'help') { continue }
            if (-not $rtSrc.Contains("'$c'")) {
                [void]$warnings.Add("runtime-profiles profile $($prof.id) references command '$c' not found as literal in os-runtime.ps1 ValidateSet (verify manually)")
                Add-Finding -File 'runtime-profiles.json' -Expected "os-runtime knows '$c'" -Actual 'not found as substring' -Severity 'warn'
            }
        }
    }

    $readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw
    $unsafe = @(
        @{ re = '(?i)skipped\s*=\s*passed'; msg = 'unsafe wording: skipped = passed' }
        @{ re = '(?i)warn(ing)?\s*=\s*pass'; msg = 'unsafe wording: warn = pass' }
    )
    foreach ($u in $unsafe) {
        if ($readme -match $u.re) {
            [void]$failures.Add("README.md: $($u.msg)")
            Add-Finding -File 'README.md' -Expected 'no false-green phrasing' -Actual $u.msg -Severity 'fail'
        }
    }

    foreach ($docName in @('ARCHITECTURE.md', 'INDEX.md', 'docs/QUICKSTART.md', 'docs/VALIDATION.md', 'docs/CONTRACT-TESTS.md', 'docs/SAFE-APPLY.md', 'docs/COMPONENTS.md', 'docs/COMPATIBILITY.md', 'docs/LIFECYCLE.md', 'docs/DISTRIBUTION.md', 'docs/SECURITY-LINT.md', 'docs/OPERATOR-JOURNAL.md', 'docs/RELEASE-READINESS.md', 'docs/TROUBLESHOOTING.md', 'docs/PROJECT-BOOTSTRAP.md', 'docs/CAPABILITIES.md', 'docs/QUALITY-GATES.md', 'policies/deprecation.md')) {
        $pDoc = Join-Path $RepoRoot $docName
        if (-not (Test-Path -LiteralPath $pDoc)) { continue }
        $body = Get-Content -LiteralPath $pDoc -Raw
        foreach ($u in $unsafe) {
            if ($body -match $u.re) {
                [void]$failures.Add("$docName : $($u.msg)")
                Add-Finding -File $docName -Expected 'no false-green phrasing' -Actual $u.msg -Severity 'fail'
            }
        }
    }

    $archPath = Join-Path $RepoRoot 'ARCHITECTURE.md'
    if (Test-Path -LiteralPath $archPath) {
        $archText = Get-Content -LiteralPath $archPath -Raw
        $archTerms = @('Claude OS Runtime', 'os-manifest.json', 'init-project.ps1', 'Invariants')
        $vp = $om.validationPolicy
        if ($null -ne $vp -and $vp.PSObject.Properties.Name -contains 'releaseContract') {
            $rc = $vp.releaseContract
            if ($null -ne $rc -and $rc.PSObject.Properties.Name -contains 'architectureRequiredSubstrings') {
                $archTerms = @($rc.architectureRequiredSubstrings | ForEach-Object { [string]$_ })
            }
        }
        foreach ($term in $archTerms) {
            if (-not [string]::IsNullOrWhiteSpace($term) -and -not $archText.Contains($term)) {
                [void]$failures.Add("ARCHITECTURE.md missing release-contract substring: $term")
                Add-Finding -File 'ARCHITECTURE.md' -Expected $term -Actual 'missing' -Severity 'fail'
            }
        }
    }

    $claudePath = Join-Path $RepoRoot 'CLAUDE.md'
    if (Test-Path -LiteralPath $claudePath) {
        $claudeRaw = Get-Content -LiteralPath $claudePath -Raw
        foreach ($m in [regex]::Matches($claudeRaw, '\]\((policies/[A-Za-z0-9._/-]+\.md)\)')) {
            $pol = $m.Groups[1].Value
            $polFull = Join-Path $RepoRoot ($pol -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $polFull)) {
                [void]$failures.Add("CLAUDE.md links missing policy file: $pol")
                Add-Finding -File 'CLAUDE.md' -Expected $pol -Actual 'missing' -Severity 'fail'
            }
        }
    }

    foreach ($pwCmd in [regex]::Matches($readme, '(?im)(?:^|\n)\s*(?:pwsh|powershell)[^\n]*?(tools/[A-Za-z0-9._/-]+\.ps1)')) {
        $rel = $pwCmd.Groups[1].Value -replace '\\', '/'
        $pth = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $pth)) {
            [void]$failures.Add("README Get-started style command references missing script: $rel")
            Add-Finding -File 'README.md' -Expected $rel -Actual 'missing' -Severity 'fail'
        }
    }

    if ($readme -match '(?is)## Get started\s*(.+?)(?:\r?\n## |\Z)') {
        $gs = $Matches[1]
        if ($gs -notmatch 'os-runtime\.ps1') {
            [void]$warnings.Add('README Get started should reference tools/os-runtime.ps1 as primary operator entrypoint')
            Add-Finding -File 'README.md' -Expected 'os-runtime.ps1 in Get started' -Actual 'not found in section' -Severity 'warn'
        }
    }

    foreach ($docName in @('README.md', 'INDEX.md')) {
        $dc = Get-Content -LiteralPath (Join-Path $RepoRoot $docName) -Raw
        foreach ($m in [regex]::Matches($dc, 'tools/[A-Za-z0-9._/-]+\.ps1')) {
            $rel = $m.Value -replace '\\', '/'
            if ($rel -match '/lib/') { continue }
            $pth = Join-Path $RepoRoot $rel
            if (-not (Test-Path -LiteralPath $pth)) {
                [void]$warnings.Add("$docName references path not found as file: $rel (may be future tool)")
                Add-Finding -File $docName -Expected $rel -Actual 'missing' -Severity 'warn'
            }
        }
    }

    $bm = Get-Content -LiteralPath (Join-Path $RepoRoot 'bootstrap-manifest.json') -Raw | ConvertFrom-Json
    $skillNeed = [int]$bm.skills.exact
    $skillDir = Join-Path $RepoRoot 'source/skills'
    $skillCount = @(Get-ChildItem -LiteralPath $skillDir -Directory -ErrorAction SilentlyContinue | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')
        }).Count
    if ($skillCount -ne $skillNeed) {
        [void]$failures.Add("skills count mismatch: source/skills with SKILL.md = $skillCount, manifest expects $skillNeed")
    }

    [void]$checks.Add([ordered]@{ name = 'doc-contract'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'manifests + README + CLAUDE policy refs' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-doc-contract-consistency' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-doc-contract-consistency: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
