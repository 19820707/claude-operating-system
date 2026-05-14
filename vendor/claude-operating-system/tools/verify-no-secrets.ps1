# verify-no-secrets.ps1 — Conservative secret / credential lint (read-only)
#   pwsh ./tools/verify-no-secrets.ps1
#   pwsh ./tools/verify-no-secrets.ps1 -Json
#   pwsh ./tools/verify-no-secrets.ps1 -Json -Strict   # ambiguous findings become blocking failures

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

# Paths that intentionally contain redaction / probe strings (do not pattern-scan body).
$script:SkipContentScanRel = [string[]]@(
    'tools/verify-os-health.ps1',
    'tools/lib/safe-output.ps1',
    'tools/verify-no-secrets.ps1'
)

$script:TextExtensions = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('.md', '.json', '.jsonl', '.yaml', '.yml', '.txt', '.toml', '.sh', '.env.example'),
    [System.StringComparer]::OrdinalIgnoreCase
)

# High-confidence (blocking) patterns: id, [regex] pattern
$script:FailPatterns = @(
    @{ id = 'pem-private-block'; re = [regex]::new('-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----', [System.Text.RegularExpressions.RegexOptions]::Multiline) },
    @{ id = 'aws-access-key-id'; re = [regex]::new('\bAKIA[0-9A-Z]{16}\b') },
    @{ id = 'aws-session-key-id'; re = [regex]::new('\bASIA[0-9A-Z]{16}\b') },
    @{ id = 'google-api-key'; re = [regex]::new('\bAIza[0-9A-Za-z_-]{35}\b') },
    @{ id = 'stripe-live-secret'; re = [regex]::new('sk_live_[0-9a-zA-Z]{20,}') },
    @{ id = 'stripe-restricted-live'; re = [regex]::new('rk_live_[0-9a-zA-Z]{20,}') },
    @{ id = 'github-classic-pat'; re = [regex]::new('ghp_[A-Za-z0-9]{36,}\b') },
    @{ id = 'github-fine-pat'; re = [regex]::new('github_pat_[A-Za-z0-9_]{20,}\b') },
    @{ id = 'slack-bot-token'; re = [regex]::new('xox[borspa]-[0-9]{8,}-[0-9A-Za-z-]{10,}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) },
    @{ id = 'anthropic-api-key'; re = [regex]::new('sk-ant-api03-[A-Za-z0-9_-]{20,}\b') },
    @{ id = 'openai-project-key'; re = [regex]::new('sk-proj-[A-Za-z0-9_-]{20,}\b') }
)

# Ambiguous: warn in default mode; fail when -Strict
$script:WarnPatterns = @(
    @{ id = 'assignment-api-key'; re = [regex]::new('(?i)\bapi[_-]?key\s*[=:]\s*[''"][^''"\r\n]{20,}[''"]') },
    @{ id = 'assignment-secret'; re = [regex]::new('(?i)\b(client_)?secret\s*[=:]\s*[''"][^''"\r\n]{12,}[''"]') },
    @{ id = 'assignment-token'; re = [regex]::new('(?i)\btoken\s*[=:]\s*[''"][^''"\r\n]{24,}[''"]') },
    @{ id = 'bearer-long'; re = [regex]::new('(?i)\bBearer\s+[A-Za-z0-9_\-\.+/=]{40,}\b') },
    @{ id = 'jwt-shape'; re = [regex]::new('[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}') },
    @{ id = 'github-pat-short'; re = [regex]::new('ghp_[A-Za-z0-9]{10,35}\b') }
)

function Get-RelFromRepo {
    param([string]$FullPath)
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $full.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Test-EnvPathTracked {
    param([string]$RelPath)
    if ($RelPath -match '(?i)(^|/)\.env($|\.)') { return $true }
    return $false
}

function Test-GitignoreLogs {
    param([string]$RawGitignore)
    if ([string]::IsNullOrWhiteSpace($RawGitignore)) { return $false }
    foreach ($line in @($RawGitignore -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.StartsWith('#')) { continue }
        if ($t -match '(?i)^/logs/') { return $true }
        if ($t -eq 'logs/' -or $t -eq '/logs/' ) { return $true }
        if ($t -match '(?i)^/logs/\*') { return $true }
    }
    return $false
}

function Get-TrackedFiles {
    $rootGit = Join-Path $RepoRoot '.git'
    if (-not (Test-Path -LiteralPath $rootGit)) { return $null }
    Push-Location $RepoRoot
    try {
        $raw = & git ls-files -z 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        $s = if ($null -eq $raw) { '' } elseif ($raw -is [array]) { $raw -join '' } else { [string]$raw }
        if ([string]::IsNullOrEmpty($s)) { return @() }
        return @($s -split [char]0, [System.StringSplitOptions]::RemoveEmptyEntries)
    }
    finally {
        Pop-Location
    }
}

function Add-Finding {
    param([string]$Rel, [string]$Rule, [string]$Severity, [int]$Line)
    [void]$script:findings.Add([ordered]@{
            file     = $Rel
            line     = [int]$Line
            rule     = $Rule
            severity = $Severity
        })
}

function Invoke-PatternOnText {
    param(
        [string]$RelPath,
        [string]$Text,
        [array]$PatternDefs,
        [string]$Severity
    )
    foreach ($def in $PatternDefs) {
        $ms = $def.re.Matches($Text)
        foreach ($m in $ms) {
            $pre = $Text.Substring(0, [Math]::Min($m.Index, $Text.Length))
            $line = 1 + @($pre -split "`r?`n").Count - 1
            if ($line -lt 1) { $line = 1 }
            $snippet = Redact-SensitiveText -Text $m.Value -MaxLength 80
            $msg = "$RelPath`:$line $($def.id) ($snippet)"
            if ($Severity -eq 'fail') {
                [void]$script:failures.Add($msg)
            }
            else {
                [void]$script:warnings.Add($msg)
            }
            Add-Finding -Rel $RelPath -Rule ([string]$def.id) -Severity $Severity -Line $line
        }
    }
}

try {
    $gitFiles = Get-TrackedFiles
    if ($null -eq $gitFiles) {
        [void]$warnings.Add('no .git: cannot verify tracked .env files; scan uses working tree paths only')
    }
    else {
        foreach ($rel in $gitFiles) {
            $norm = $rel.Replace('\', '/')
            if (Test-EnvPathTracked -RelPath $norm) {
                [void]$failures.Add("tracked env-style file: $norm")
                Add-Finding -Rel $norm -Rule 'tracked-dot-env' -Severity 'fail' -Line 1
            }
        }
    }

    $giPath = Join-Path $RepoRoot '.gitignore'
    if (-not (Test-Path -LiteralPath $giPath)) {
        [void]$failures.Add('missing .gitignore (cannot confirm logs/ are ignored)')
    }
    else {
        $giRaw = Get-Content -LiteralPath $giPath -Raw -Encoding utf8
        if (-not (Test-GitignoreLogs -RawGitignore $giRaw)) {
            [void]$failures.Add('.gitignore must ignore generated logs (expected /logs/ or equivalent)')
            Add-Finding -Rel '.gitignore' -Rule 'logs-gitignore' -Severity 'fail' -Line 1
        }
    }

    $pathsToScan = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $always = @(
        'OS_WORKSPACE_CONTEXT.template.md',
        'OPERATOR_JOURNAL.template.md'
    )
    foreach ($a in $always) {
        $f = Join-Path $RepoRoot $a
        if (Test-Path -LiteralPath $f) { [void]$pathsToScan.Add((Get-RelFromRepo -FullPath $f)) }
    }

    $dirPrefixes = @('docs/', 'examples/', 'recipes/', 'playbooks/', 'policies/', 'templates/', 'source/skills/')
    foreach ($pfx in $dirPrefixes) {
        $d = Join-Path $RepoRoot ($pfx.TrimEnd('/') )
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = Get-RelFromRepo -FullPath $_.FullName
            if (-not $rel) { return }
            if ($rel -match '(?i)/node_modules/') { return }
            if ($rel -match '(?i)templates/invariant-engine/node_modules/') { return }
            $ext = $_.Extension
            if (-not $script:TextExtensions.Contains($ext)) { return }
            [void]$pathsToScan.Add($rel)
        }
    }

    foreach ($rootMd in @('CLAUDE.md', 'INDEX.md', 'ARCHITECTURE.md', 'SECURITY.md', 'GIT-RECOVERY.md')) {
        $f = Join-Path $RepoRoot $rootMd
        if (Test-Path -LiteralPath $f) { [void]$pathsToScan.Add((Get-RelFromRepo -FullPath $f)) }
    }

    if ($null -ne $gitFiles) {
        foreach ($rel in $gitFiles) {
            $norm = $rel.Replace('\', '/')
            if ($norm -match '(?i)/node_modules/') { continue }
            if ($norm -match '(?i)templates/invariant-engine/node_modules/') { continue }
            $ext = [System.IO.Path]::GetExtension($norm)
            if (-not $script:TextExtensions.Contains($ext)) { continue }
            [void]$pathsToScan.Add($norm)
        }
    }

    foreach ($rel in @($pathsToScan | Sort-Object)) {
        if ($script:SkipContentScanRel -contains $rel) { continue }
        $full = Join-Path $RepoRoot ($rel -replace '/', [char][System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full)) { continue }
        try {
            $bytes = [System.IO.File]::ReadAllBytes($full)
            if ($bytes.Length -gt 2MB) {
                [void]$warnings.Add("skipped large file for pattern scan: $rel")
                continue
            }
            if ($bytes -contains 0) { continue }
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
        }
        catch {
            [void]$warnings.Add("unreadable for scan: $rel")
            continue
        }

        Invoke-PatternOnText -RelPath $rel -Text $raw -PatternDefs $script:FailPatterns -Severity 'fail'
        Invoke-PatternOnText -RelPath $rel -Text $raw -PatternDefs $script:WarnPatterns -Severity 'warn'
    }
}
catch {
    [void]$failures.Add((Redact-SensitiveText -Text $_.Exception.Message -MaxLength 400))
}

if ($Strict -and $warnings.Count -gt 0) {
    foreach ($w in @($warnings)) { [void]$failures.Add($w) }
    $warnings.Clear()
}

[void]$checks.Add([ordered]@{
        name   = 'no-secrets'
        status = $(if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' })
        detail = 'tracked .env, .gitignore logs/, PEM and common provider key shapes; ambiguous assignments in docs/examples'
    })

$sw.Stop()
$st = if ($failures.Count -gt 0) { 'fail' } elseif ($warnings.Count -gt 0) { 'warn' } else { 'ok' }
$env = New-OsValidatorEnvelope -Tool 'verify-no-secrets' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
    -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

if ($Json) {
    $env | ConvertTo-Json -Depth 12 -Compress | Write-Output
}
else {
    Write-Host "verify-no-secrets: $($env.status)"
    foreach ($f in @($env.failures)) { Write-Host "FAIL: $f" }
    foreach ($w in @($env.warnings)) { Write-Host "WARN: $w" }
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
