# safe-output.ps1 — Shared redaction and concise output helpers
# Dot-source from tools:
#   . "$PSScriptRoot/lib/safe-output.ps1"

function Redact-SensitiveText {
    param(
        [AllowNull()]
        [string]$Text,
        [int]$MaxLength = 240
    )

    if ($null -eq $Text) { return '' }

    $safe = [string]$Text
    $patterns = @(
        '(?i)(bearer\s+)[a-z0-9._~+\-/]+=*',
        '(?i)(api[_-]?key\s*[=:]\s*)[^\s''"`]+',
        '(?i)(token\s*[=:]\s*)[^\s''"`]+',
        '(?i)(secret\s*[=:]\s*)[^\s''"`]+',
        '(?i)(password\s*[=:]\s*)[^\s''"`]+',
        'ghp_[A-Za-z0-9_]{20,}',
        'github_pat_[A-Za-z0-9_]{20,}',
        'sk-[A-Za-z0-9]{20,}',
        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    )

    foreach ($pattern in $patterns) {
        $safe = [regex]::Replace($safe, $pattern, {
            param($m)
            if ($m.Groups.Count -gt 1 -and $m.Groups[1].Success) {
                return $m.Groups[1].Value + '[REDACTED]'
            }
            return '[REDACTED]'
        })
    }

    # Invariant: user-facing output never dumps raw stack traces or huge generated JSON.
    $safe = [regex]::Replace($safe, '(?im)^\s*at\s+.+$', '  at [REDACTED-STACK]')
    $safe = [regex]::Replace($safe, '(?s)\{\s*"[^\n]{120,}', '{ [REDACTED-LARGE-JSON]')

    if ($MaxLength -gt 0 -and $safe.Length -gt $MaxLength) {
        return $safe.Substring(0, $MaxLength) + '...'
    }
    return $safe
}

function Write-StatusLine {
    param(
        [string]$Status,
        [string]$Name,
        [string]$Detail = ''
    )
    $line = "  $($Status.ToUpper().PadRight(5)) $Name"
    if ($Detail) { $line += " - $(Redact-SensitiveText -Text $Detail -MaxLength 180)" }
    Write-Host $line
}
