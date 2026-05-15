# safe-apply.ps1 — Shared helpers for dry-run / WhatIf detection (dot-source only)

function Get-SafeApplySignalsFromScriptText {
    param([string]$Raw)
    if ([string]::IsNullOrEmpty($Raw)) {
        return [pscustomobject]@{ ShouldProcess = $false; DryRun = $false; WhatIf = $false }
    }
    $hasShould = [bool]($Raw -match '(?s)\[CmdletBinding\([^\]]*SupportsShouldProcess\s*=\s*\$true')
    $hasDry = [bool]($Raw -match '(?i)\[switch\]\s*\$DryRun\b')
    $hasWhatIf = [bool]($Raw -match '(?i)\[switch\]\s*\$WhatIf\b')
    return [pscustomobject]@{
        ShouldProcess = $hasShould
        DryRun        = $hasDry
        WhatIf        = $hasWhatIf
    }
}

function Test-SafeApplyDryRunFamily {
    param([object]$Signals)
    return [bool]($Signals.ShouldProcess -or $Signals.DryRun -or $Signals.WhatIf)
}

function Get-SafeApplyForwardArgs {
    param(
        [object]$Signals,
        [bool]$WantDryRun
    )
    $args = [System.Collections.Generic.List[string]]::new()
    if (-not $WantDryRun) { return @($args) }
    if ($Signals.DryRun) {
        [void]$args.Add('-DryRun')
        return @($args)
    }
    if ($Signals.ShouldProcess -or $Signals.WhatIf) {
        [void]$args.Add('-WhatIf')
        return @($args)
    }
    return @()
}
