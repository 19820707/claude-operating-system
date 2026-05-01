# init-project.ps1 — Bootstrap a new project with full .claude/ skeleton (Windows)
#
# Path style (recommended):
#   powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -ProjectPath "c:\Users\you\claude\novo-projeto"
#
# Name style (parent defaults to %USERPROFILE%\claude):
#   powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -Name novo-projeto
#
# Protected files (never overwritten): .claude/session-state.md, .claude/learning-log.md
# CLAUDE.md: skipped if it already exists unless -Force
# Commands, agents, critical-surfaces, policies, scripts: always refreshed from templates

[CmdletBinding(DefaultParameterSetName = 'Name')]
param(
    [Parameter(ParameterSetName = 'ProjectPath', Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(ParameterSetName = 'Name', Mandatory = $true, Position = 0)]
    [string]$Name,

    [Parameter(ParameterSetName = 'Name')]
    [string]$Parent = "$env:USERPROFILE\claude",

    [string]$Source = "",

    [switch]$Force,

    [switch]$SkipGitInit,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $Source) {
    $Source = $PSScriptRoot
}

$templates = Join-Path $Source "templates"
$policiesSrc = Join-Path $Source "policies"
$heuristicsSrc = Join-Path $Source "heuristics"

function Get-InitValidationExpectations {
    param([string]$SourceRoot)
    $defaults = @{ slashCommands = 10; agents = 5; criticalSurfaces = 5 }
    $manifestPath = Join-Path $SourceRoot "bootstrap-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return $defaults
    }
    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($null -eq $m.initProjectValidation) {
            return $defaults
        }
        $v = $m.initProjectValidation
        return @{
            slashCommands    = [int]$v.slashCommands
            agents           = [int]$v.agents
            criticalSurfaces = [int]$v.criticalSurfaces
        }
    } catch {
        Write-Host "  (warn) could not read bootstrap-manifest.json; using built-in defaults"
        return $defaults
    }
}

function Resolve-ProjectRoot {
    if ($PSCmdlet.ParameterSetName -eq 'ProjectPath') {
        if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
            throw "-ProjectPath cannot be empty."
        }
        return [System.IO.Path]::GetFullPath($ProjectPath)
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "-Name cannot be empty."
    }
    if ($Name -match '[\\/]') {
        throw "Use -Name as a single folder name (no path separators), or use -ProjectPath for a full path."
    }
    return [System.IO.Path]::GetFullPath((Join-Path $Parent $Name))
}

$ProjectRoot = Resolve-ProjectRoot

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
        Write-Host "  mkdir  $Path"
    }
}

function Copy-FileAlways {
    param([string]$From, [string]$To)
    $dir = Split-Path $To -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Host "  mkdir  $dir"
    }
    if ($DryRun) {
        Write-Host "  [dry]  $From -> $To"
        return
    }
    Copy-Item -LiteralPath $From -Destination $To -Force
    Write-Host "  copied $From -> $To"
}

function Copy-IfMissing {
    param([string]$From, [string]$To, [string]$Label)
    if (Test-Path -LiteralPath $To) {
        Write-Host "  (skip) $Label already exists: $To"
        return
    }
    Copy-FileAlways -From $From -To $To
}

function Copy-ClaudeTemplate {
    param([string]$From, [string]$To)
    if (Test-Path -LiteralPath $To) {
        if (-not $Force) {
            Write-Host "  (skip) CLAUDE.md already exists (use -Force to overwrite): $To"
            return
        }
        Write-Host "  (force) overwriting CLAUDE.md"
    }
    Copy-FileAlways -From $From -To $To
}

function Ensure-GitIgnore {
    param([string]$Root)
    $lines = @(
        ".claude/*.tmp",
        ".claude/*.local.json"
    )
    $path = Join-Path $Root ".gitignore"
    if ($DryRun) {
        Write-Host "  [dry]  ensure .gitignore entries at $path"
        return
    }
    $existing = @()
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path
    }
    $toAdd = foreach ($l in $lines) {
        if ($existing -notcontains $l) { $l }
    }
    if ($toAdd.Count -eq 0) { return }
    $append = (($toAdd -join "`n").TrimEnd() + "`n")
    if (Test-Path -LiteralPath $path) {
        Add-Content -LiteralPath $path -Value $append -Encoding utf8
        Write-Host "  appended .gitignore rules"
    } else {
        Set-Content -LiteralPath $path -Value $append -Encoding utf8
        Write-Host "  created .gitignore"
    }
}

Write-Host ""
Write-Host "claude-operating-system init-project"
Write-Host "Source      : $Source"
Write-Host "Project root: $ProjectRoot"
if ($DryRun) { Write-Host "[DRY RUN - no files written]" }
Write-Host ""

if (-not (Test-Path -LiteralPath $templates)) {
    throw "Templates not found at $templates. Pass -Source to your claude-operating-system clone."
}
if (-not (Test-Path -LiteralPath $policiesSrc)) {
    throw "Policies not found at $policiesSrc. Pass -Source to your claude-operating-system clone."
}

$parentDir = Split-Path $ProjectRoot -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
    Ensure-Dir $parentDir
}
Ensure-Dir $ProjectRoot

Ensure-Dir (Join-Path $ProjectRoot ".claude")
Ensure-Dir (Join-Path $ProjectRoot ".claude\commands")
Ensure-Dir (Join-Path $ProjectRoot ".claude\scripts")
Ensure-Dir (Join-Path $ProjectRoot ".claude\policies")
Ensure-Dir (Join-Path $ProjectRoot ".claude\agents")
Ensure-Dir (Join-Path $ProjectRoot ".claude\heuristics")
Ensure-Dir (Join-Path $ProjectRoot ".claude\critical-surfaces")

if (-not $SkipGitInit) {
    if ($DryRun) {
        Write-Host "  [dry]  git init"
    } else {
        Push-Location $ProjectRoot
        try {
            if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) {
                git init 2>&1 | Out-Host
                Write-Host "  git init"
            } else {
                Write-Host '  (skip) git init - .git already exists'
            }
        } finally {
            Pop-Location
        }
    }
}

Copy-ClaudeTemplate -From (Join-Path $templates "project-CLAUDE.md") -To (Join-Path $ProjectRoot "CLAUDE.md")
Copy-IfMissing -From (Join-Path $templates "session-state.md") -To (Join-Path $ProjectRoot ".claude\session-state.md") -Label "session-state.md"
Copy-IfMissing -From (Join-Path $templates "learning-log.md") -To (Join-Path $ProjectRoot ".claude\learning-log.md") -Label "learning-log.md"

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".claude\settings.json")) -or $Force) {
    if ((Test-Path -LiteralPath (Join-Path $ProjectRoot ".claude\settings.json")) -and $Force) {
        Write-Host "  (force) overwriting .claude\settings.json"
    }
    Copy-FileAlways -From (Join-Path $templates "settings.json") -To (Join-Path $ProjectRoot ".claude\settings.json")
} else {
    Write-Host "  (skip) settings.json already exists (use -Force to overwrite)"
}

Get-ChildItem -Path $policiesSrc -Filter "*.md" -File | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot ".claude\policies\$($_.Name)")
}

Get-ChildItem -LiteralPath (Join-Path $templates "commands") -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot ".claude\commands\$($_.Name)")
}

Get-ChildItem -LiteralPath (Join-Path $templates "agents") -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot ".claude\agents\$($_.Name)")
}

Get-ChildItem -LiteralPath (Join-Path $templates "critical-surfaces") -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot ".claude\critical-surfaces\$($_.Name)")
}

Get-ChildItem -Path (Join-Path $templates "scripts") -Filter "*.sh" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot ".claude\scripts\$($_.Name)")
}

if (Test-Path -LiteralPath $heuristicsSrc) {
    Get-ChildItem -Path $heuristicsSrc -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-FileAlways -From $_.FullName -To (Join-Path $ProjectRoot ".claude\heuristics\$($_.Name)")
    }
}

Ensure-Dir (Join-Path $ProjectRoot ".local")
$tsBudgetTemplate = Join-Path $templates "local\ts-error-budget.json"
if (Test-Path -LiteralPath $tsBudgetTemplate) {
    Copy-IfMissing -From $tsBudgetTemplate -To (Join-Path $ProjectRoot ".local\ts-error-budget.json") -Label "ts-error-budget.json"
}

Ensure-GitIgnore $ProjectRoot

Write-Host ""
Write-Host "Validation:"
if ($DryRun) {
    Write-Host "  (dry) skipped file counts (no writes performed)"
} else {
    $exp = Get-InitValidationExpectations -SourceRoot $Source
    $expectedCmd = $exp.slashCommands
    $expectedAgents = $exp.agents
    $expectedCrit = $exp.criticalSurfaces
    $cmdDir = Join-Path $ProjectRoot ".claude\commands"
    $agDir = Join-Path $ProjectRoot ".claude\agents"
    $crDir = Join-Path $ProjectRoot ".claude\critical-surfaces"

    $cmdCount = if (Test-Path -LiteralPath $cmdDir) { (Get-ChildItem -LiteralPath $cmdDir -Filter "*.md" -File).Count } else { 0 }
    $agCount = if (Test-Path -LiteralPath $agDir) { (Get-ChildItem -LiteralPath $agDir -Filter "*.md" -File).Count } else { 0 }
    $crCount = if (Test-Path -LiteralPath $crDir) { (Get-ChildItem -LiteralPath $crDir -Filter "*.md" -File).Count } else { 0 }

    $ok = $true
    if ($cmdCount -ne $expectedCmd) {
        Write-Host "  FAIL: expected $expectedCmd command templates, found $cmdCount in $cmdDir"
        $ok = $false
    } else {
        Write-Host "  OK: $cmdCount slash-command templates"
    }
    if ($agCount -ne $expectedAgents) {
        Write-Host "  FAIL: expected $expectedAgents agent templates, found $agCount in $agDir"
        $ok = $false
    } else {
        Write-Host "  OK: $agCount agent templates"
    }
    if ($crCount -ne $expectedCrit) {
        Write-Host "  FAIL: expected $expectedCrit critical-surface templates, found $crCount in $crDir"
        $ok = $false
    } else {
        Write-Host "  OK: $crCount critical-surface templates"
    }

    $ss = Join-Path $ProjectRoot ".claude\session-state.md"
    $ll = Join-Path $ProjectRoot ".claude\learning-log.md"
    if (-not (Test-Path -LiteralPath $ss)) {
        Write-Host "  FAIL: missing $ss"
        $ok = $false
    } else {
        Write-Host "  OK: session-state.md present"
    }
    if (-not (Test-Path -LiteralPath $ll)) {
        Write-Host "  FAIL: missing $ll"
        $ok = $false
    } else {
        Write-Host "  OK: learning-log.md present"
    }

    if (-not $ok) {
        throw "Validation failed. Fix template counts or paths and re-run."
    }
}

Write-Host ""
Write-Host "Done. Project scaffold ready at:"
Write-Host "  $ProjectRoot"
Write-Host ""
Write-Host 'Suggested git commit (review `git status` first):'
Write-Host ('  cd "' + $ProjectRoot + '"')
Write-Host '  git add CLAUDE.md .claude .gitignore'
Write-Host '  git commit -m "ops: bootstrap Claude operational system"'
Write-Host ""
Write-Host 'Next steps:'
Write-Host '  1. Edit CLAUDE.md - stack, branch model, critical surfaces'
Write-Host '  2. Review .claude\settings.json - allow/deny, hooks'
Write-Host ('  3. cd "' + $ProjectRoot + '" ; claude')
Write-Host '  4. Type /session-start'
Write-Host ""
