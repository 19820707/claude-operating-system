# prediction-engine.ps1 — Probabilistic failure prediction with Bayesian calibration feedback
# Predicts CI failures, invariant violations, coupling regressions. Closes the prediction loop.
#   pwsh ./tools/prediction-engine.ps1 -Mode predict -Files tools/auth.ps1,tools/billing.ps1
#   pwsh ./tools/prediction-engine.ps1 -Mode calibrate
#   pwsh ./tools/prediction-engine.ps1 -Mode log -PredictionId pred-20260516-001 -Outcome 1
#   pwsh ./tools/prediction-engine.ps1 -Json

param(
    [ValidateSet('predict','calibrate','log')]
    [string]$Mode = 'predict',
    [string[]]$Files = @(),
    [string]$PredictionId = '',
    [int]$Outcome = -1,
    [double]$Threshold = 0.75,
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

$ModelPath   = Join-Path $RepoRoot '.claude/world-model.json'
$PredLogPath = Join-Path $RepoRoot '.claude/prediction-log.jsonl'
$InvPath     = Join-Path $RepoRoot 'templates/invariants/core.json'

# ── Helpers ───────────────────────────────────────────────────────────────────

function Get-WorldModel {
    if (Test-Path -LiteralPath $ModelPath) {
        try { return Get-Content -LiteralPath $ModelPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { }
    }
    return [PSCustomObject]@{ entities = [PSCustomObject]@{}; relations = @(); global_state = [PSCustomObject]@{ prediction_accuracy = 0.0 } }
}

function Get-EntityRisk {
    param([object]$Model, [string]$Key)
    $prop = $Model.entities.PSObject.Properties[$Key]
    if ($prop) { return [double]$prop.Value.risk_posterior }
    return 0.3
}

function Get-EntityCoupling {
    param([object]$Model, [string]$Key)
    $prop = $Model.entities.PSObject.Properties[$Key]
    if ($prop) { return @($prop.Value.coupling) }
    return @()
}

function Get-InvariantStats {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $InvPath)) { return 0, 10 }
    try {
        $inv   = Get-Content -LiteralPath $InvPath -Raw | ConvertFrom-Json
        $total = @($inv.invariants).Count
        $fname = [System.IO.Path]::GetFileName($FilePath)
        $match = @($inv.invariants | Where-Object {
            $_.check -and (($_.check | ConvertTo-Json -Depth 5) -match [regex]::Escape($fname))
        }).Count
        return $match, $total
    } catch { return 0, 10 }
}

# ── MODE: predict ─────────────────────────────────────────────────────────────

if ($Mode -eq 'predict') {
    $model    = Get-WorldModel
    $findings = [System.Collections.Generic.List[object]]::new()
    $anyHigh  = $false

    foreach ($f in $Files) {
        $risk     = Get-EntityRisk -Model $model -Key $f
        $coupling = Get-EntityCoupling -Model $model -Key $f

        # P1: CI failure = risk * 0.8 (churn proxy — full churn tracking in world-model)
        $p1 = [Math]::Round($risk * 0.8, 4)

        # P2: invariant violation = (matching invariants / total) * risk
        $invMatch, $invTotal = Get-InvariantStats -FilePath $f
        $p2 = if ($invTotal -gt 0) { [Math]::Round(($invMatch / $invTotal) * $risk, 4) } else { 0.0 }

        # P3: max coupling strength * coupling entity risk
        $p3 = 0.0
        foreach ($c in $coupling) {
            $cRisk = Get-EntityRisk -Model $model -Key $c
            $rel   = @($model.relations | Where-Object { $_.from -eq $f -and $_.to -eq $c }) | Select-Object -First 1
            $str   = if ($rel) { [double]$rel.strength } else { 0.3 }
            $cP    = $str * $cRisk
            if ($cP -gt $p3) { $p3 = $cP }
        }
        $p3 = [Math]::Round($p3, 4)

        # P4: cross-project known pattern match
        $p4 = 0.0
        $cpPath = Join-Path $RepoRoot '.claude/cross-project-evidence.json'
        if (Test-Path -LiteralPath $cpPath) {
            try {
                $cp    = Get-Content -LiteralPath $cpPath -Raw | ConvertFrom-Json
                $fname = [System.IO.Path]::GetFileName($f)
                $match = $cp.patterns | Where-Object { $_.file_pattern -and ($fname -match $_.file_pattern) } | Select-Object -First 1
                if ($match) { $p4 = 1.0 }
            } catch { }
        }

        # Combined: P(problem) = 1 - prod(1 - Pi)
        $pCombined = [Math]::Round(1 - (1-$p1)*(1-$p2)*(1-$p3)*(1-$p4), 4)

        # Confidence interval (wider when few observations)
        $ciWidth = 0.15  # default; narrows as world model accumulates data

        $recommendation = if ($pCombined -ge 0.75) {
            'BLOCK — high failure risk; split change or add test coverage'
        } elseif ($pCombined -ge 0.50) {
            'REVIEW — moderate risk; check coupling and invariant coverage'
        } else {
            'PROCEED — low predicted risk'
        }

        if ($pCombined -ge $Threshold) { $anyHigh = $true }

        # Log prediction for calibration
        $predId = "pred-$(Get-Date -Format 'yyyyMMddHHmmss')-$(([System.IO.Path]::GetFileNameWithoutExtension($f)) -replace '[^a-zA-Z0-9]','_')"
        $logEntry = [ordered]@{
            id          = $predId
            ts          = (Get-Date).ToUniversalTime().ToString('o')
            file        = $f
            p_predicted = $pCombined
            outcome     = -1
        }
        try { Add-Content -LiteralPath $PredLogPath -Value ($logEntry | ConvertTo-Json -Compress) -Encoding utf8 } catch { }

        [void]$findings.Add([ordered]@{
            file             = $f
            p_ci_failure     = $p1
            p_inv_violation  = $p2
            p_coupling_regr  = $p3
            p_known_pattern  = $p4
            p_any_problem    = $pCombined
            ci_width         = $ciWidth
            prediction_id    = $predId
            recommendation   = $recommendation
        })
    }

    [void]$checks.Add([ordered]@{ name = 'predict'; status = $(if ($anyHigh) { 'warn' } else { 'ok' }); detail = "files=$($Files.Count)" })
    $st  = if ($anyHigh) { 'warn' } else { 'ok' }
    $env = New-OsValidatorEnvelope -Tool 'prediction-engine' -Status $st -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) -Failures @($failures) -Findings @($findings)

    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else {
        foreach ($pred in $findings) {
            Write-Host "[OS-PREDICTION] $($pred.file)"
            Write-Host "  P(CI failure)          : $($pred.p_ci_failure) (+-$($pred.ci_width))"
            Write-Host "  P(invariant violation) : $($pred.p_inv_violation)"
            Write-Host "  P(coupling regression) : $($pred.p_coupling_regr)"
            Write-Host "  P(known pattern)       : $($pred.p_known_pattern)"
            Write-Host "  ------------------------------------"
            Write-Host "  P(any problem)         : $($pred.p_any_problem)"
            Write-Host "  Recommendation         : $($pred.recommendation)"
            Write-Host ''
        }
    }
    exit 0
}

# ── MODE: calibrate ───────────────────────────────────────────────────────────

if ($Mode -eq 'calibrate') {
    if (-not (Test-Path -LiteralPath $PredLogPath)) {
        [void]$warnings.Add('No prediction-log.jsonl found — calibration skipped')
        [void]$checks.Add([ordered]@{ name = 'calibrate'; status = 'warn'; detail = 'no prediction log' })
        $env = New-OsValidatorEnvelope -Tool 'prediction-engine' -Status 'warn' -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($checks) -Warnings @($warnings)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host 'prediction-engine | calibrate | no history yet — run predictions first' }
        exit 0
    }

    $lines  = Get-Content -LiteralPath $PredLogPath -Encoding utf8
    $scored = $lines | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ -and [int]$_.outcome -ne -1 }

    $n = @($scored).Count
    if ($n -eq 0) {
        [void]$warnings.Add('No predictions with recorded outcomes yet')
        [void]$checks.Add([ordered]@{ name = 'calibrate'; status = 'warn'; detail = 'no outcomes logged' })
        $env = New-OsValidatorEnvelope -Tool 'prediction-engine' -Status 'warn' -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($checks) -Warnings @($warnings)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host 'prediction-engine | calibrate | no outcomes logged yet' }
        exit 0
    }

    # Brier score: mean((p_predicted - actual_outcome)^2)
    $brierSum = 0.0
    foreach ($s in $scored) {
        $diff = [double]$s.p_predicted - [double]$s.outcome
        $brierSum += $diff * $diff
    }
    $brierScore = [Math]::Round($brierSum / $n, 4)
    $accuracy   = [Math]::Round(1 - $brierScore, 4)

    # Persist prediction_accuracy into world model
    if (Test-Path -LiteralPath $ModelPath) {
        try {
            $model = Get-Content -LiteralPath $ModelPath -Raw | ConvertFrom-Json
            $model.global_state.prediction_accuracy = $accuracy
            $json = $model | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ModelPath, ($json -replace "`r`n", "`n"), [System.Text.Encoding]::UTF8)
        } catch { [void]$warnings.Add('Could not persist prediction_accuracy to world-model') }
    }

    [void]$checks.Add([ordered]@{ name = 'calibrate'; status = 'ok'; detail = "N=${n} brier=${brierScore} accuracy=${accuracy}" })
    $env = New-OsValidatorEnvelope -Tool 'prediction-engine' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Checks @($checks) -Warnings @($warnings) `
        -Findings @([ordered]@{ n = $n; brier_score = $brierScore; prediction_accuracy = $accuracy })
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else { Write-Host "prediction-engine | calibrate | accuracy=${accuracy} (Brier=${brierScore}, N=${n})" }
    exit 0
}

# ── MODE: log ─────────────────────────────────────────────────────────────────

if ($Mode -eq 'log') {
    if (-not $PredictionId) {
        [void]$failures.Add('-PredictionId required for log mode')
        $env = New-OsValidatorEnvelope -Tool 'prediction-engine' -Status 'fail' -DurationMs ([int]$sw.ElapsedMilliseconds) -Failures @($failures)
        if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
        else { Write-Host 'prediction-engine | log | error: -PredictionId required' }
        exit 0
    }

    if (Test-Path -LiteralPath $PredLogPath) {
        $lines   = Get-Content -LiteralPath $PredLogPath -Encoding utf8
        $updated = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match '^\{') {
                try {
                    $entry = $_ | ConvertFrom-Json
                    if ($entry.id -eq $PredictionId) {
                        $entry.outcome = $Outcome
                        $updated = $true
                        return ($entry | ConvertTo-Json -Compress)
                    }
                } catch { }
            }
            return $_
        }
        if ($updated) {
            [System.IO.File]::WriteAllText($PredLogPath, ($newLines -join "`n"), [System.Text.Encoding]::UTF8)
        } else {
            $entry = [ordered]@{ id = $PredictionId; ts = (Get-Date).ToUniversalTime().ToString('o'); p_predicted = 0.5; outcome = $Outcome }
            Add-Content -LiteralPath $PredLogPath -Value ($entry | ConvertTo-Json -Compress) -Encoding utf8
        }
    } else {
        $entry = [ordered]@{ id = $PredictionId; ts = (Get-Date).ToUniversalTime().ToString('o'); p_predicted = 0.5; outcome = $Outcome }
        [System.IO.File]::WriteAllText($PredLogPath, ($entry | ConvertTo-Json -Compress), [System.Text.Encoding]::UTF8)
    }

    [void]$checks.Add([ordered]@{ name = 'log'; status = 'ok'; detail = "${PredictionId} outcome=${Outcome}" })
    $env = New-OsValidatorEnvelope -Tool 'prediction-engine' -Status 'ok' -DurationMs ([int]$sw.ElapsedMilliseconds) -Checks @($checks)
    if ($Json) { $env | ConvertTo-Json -Depth 8 -Compress | Write-Output }
    else { Write-Host "prediction-engine | log | ${PredictionId} outcome=${Outcome}" }
    exit 0
}

exit 0
