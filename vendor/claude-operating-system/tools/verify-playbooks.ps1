# verify-playbooks.ps1 — playbook-manifest.json + Markdown section contract
#   pwsh ./tools/verify-playbooks.ps1 [-Json] [-Strict]

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Strict
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

$sectionPatterns = @(
    @{ n = 'Purpose'; re = '(?m)^##\s+Purpose\b' }
    @{ n = 'Trigger conditions'; re = '(?m)^##\s+Trigger conditions\b' }
    @{ n = 'Required inputs'; re = '(?m)^##\s+Required inputs\b' }
    @{ n = 'Risk level'; re = '(?m)^##\s+Risk level\b' }
    @{ n = 'Required approvals'; re = '(?m)^##\s+Required approvals\b' }
    @{ n = 'Preflight checks'; re = '(?m)^##\s+Preflight checks\b' }
    @{ n = 'Execution steps'; re = '(?m)^##\s+Execution steps\b' }
    @{ n = 'Validation steps'; re = '(?m)^##\s+Validation steps\b' }
    @{ n = 'Rollback / abort criteria'; re = '(?m)^##\s+Rollback / abort criteria\b' }
    @{ n = 'Evidence to collect'; re = '(?m)^##\s+Evidence to collect\b' }
    @{ n = 'Expected outputs'; re = '(?m)^##\s+Expected outputs\b' }
    @{ n = 'Failure reporting'; re = '(?m)^##\s+Failure reporting\b' }
)

try {
    $mfPath = Join-Path $RepoRoot 'playbook-manifest.json'
    $schemaPath = Join-Path $RepoRoot 'schemas/playbook-manifest.schema.json'
    if (-not (Test-Path -LiteralPath $mfPath)) { throw 'missing playbook-manifest.json' }
    if (-not (Test-Path -LiteralPath $schemaPath)) { throw 'missing schemas/playbook-manifest.schema.json' }
    $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $mf = Get-Content -LiteralPath $mfPath -Raw | ConvertFrom-Json

    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pb in @($mf.playbooks)) {
        $id = [string]$pb.id
        if ($ids.Contains($id)) {
            [void]$failures.Add("duplicate playbook id: $id")
            continue
        }
        [void]$ids.Add($id)

        $rel = [string]$pb.path
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            [void]$failures.Add("playbook path missing: $rel")
            continue
        }
        if ($rel -notmatch '^playbooks/[a-z0-9-]+\.md$') {
            [void]$failures.Add("playbook path must be playbooks/<slug>.md: $rel")
        }

        $risk = [string]$pb.riskLevel
        $ap = @($pb.requiresApprovalFor | ForEach-Object { [string]$_ })
        if ($risk -in @('high', 'critical') -and $ap.Count -eq 0) {
            [void]$failures.Add("playbook $id risk $risk must declare non-empty requiresApprovalFor in manifest")
        }

        $body = Get-Content -LiteralPath $full -Raw

        foreach ($sec in $sectionPatterns) {
            if ($body -notmatch $sec.re) {
                $msg = "playbook $id missing section: $($sec.n) ($rel)"
                if ($Strict) {
                    [void]$failures.Add($msg)
                }
                else {
                    [void]$warnings.Add($msg)
                }
            }
        }

    }

    $pbRoot = Join-Path $RepoRoot 'playbooks'
    if (Test-Path -LiteralPath $pbRoot) {
        foreach ($f in @(Get-ChildItem -LiteralPath $pbRoot -Filter '*.md' -File | Where-Object { $_.Name -ne 'README.md' })) {
            $relPath = ('playbooks/' + $f.Name) -replace '\\', '/'
            $listed = $false
            foreach ($pb in @($mf.playbooks)) {
                if ([string]$pb.path -eq $relPath) { $listed = $true; break }
            }
            if (-not $listed) {
                [void]$failures.Add("playbooks/$($f.Name) exists but is not listed in playbook-manifest.json")
            }
        }
    }

    [void]$checks.Add([ordered]@{ name = 'playbooks'; status = $(if ($failures.Count -gt 0) { 'fail' } else { 'ok' }); detail = 'playbook-manifest + Markdown contract' })
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-playbooks' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-playbooks: $($env.status)"
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
