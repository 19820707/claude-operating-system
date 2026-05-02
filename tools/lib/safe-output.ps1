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
        '(?i)(authorization:\s*bearer\s+)[^\s]+',
        '(?i)(api[_-]?key\s*[=:]\s*)[^\s''"`]+',
        '(?i)(x-api-key\s*:\s*)[^\s]+',
        '(?i)(token\s*[=:]\s*)[^\s''"`]+',
        '(?i)(secret\s*[=:]\s*)[^\s''"`]+',
        '(?i)(password\s*[=:]\s*)[^\s''"`]+',
        '(?i)(passwd\s*[=:]\s*)[^\s''"`]+',
        '(?i)(connection\s*string\s*[=:]\s*)[^\s''"`]{8,}',
        '(?i)(mongodb(\+srv)?://)[^\s''"`]+',
        '(?i)(postgres(ql)?://)[^\s''"`]+',
        '(?i)(mysql://)[^\s''"`]+',
        '(?i)(redis://)[^\s''"`]+',
        '(?i)(AKIA[0-9A-Z]{16})',
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
    $safe = [regex]::Replace($safe, '(?s)\[\s*\{\s*"[^\n]{120,}', '[ [REDACTED-LARGE-JSON]')
    # Long temp / workspace paths (reduce noise; keep tail for orientation)
    $safe = [regex]::Replace(
        $safe,
        '(?i)([A-Za-z]:\\Users\\[^\\]+\\AppData\\Local\\Temp\\claude-os-[^\s]{16,})',
        { param($m) return '[REDACTED-TEMP]/' + (Split-Path -Path $m.Value -Leaf) }
    )

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
