# os-remediation-guidance.ps1 — Shared reason / impact / remediation text for health and doctor (dot-source only)
# Used by verify-os-health.ps1 and os-doctor.ps1; keep strings concise and free of secrets.

function New-OsHealthStepFinding {
    param(
        [string]$StepName,
        [string]$Status,
        [string]$Note = ''
    )
    $reason = if (-not [string]::IsNullOrWhiteSpace($Note)) {
        $Note.Trim()
    }
    else {
        "Health step '$StepName' reported status '$Status'."
    }
    $impact = 'CI or local release validation may fail; strict health runs treat unresolved issues as blocking.'
    $remediation = 'See docs/TROUBLESHOOTING.md, fix the underlying cause, then run: pwsh ./tools/verify-os-health.ps1 -Json'
    $strictImpact = 'verify-os-health -Strict fails if this step is warn or fail (or if os-doctor reports unexpected warnings).'
    $docsLink = 'docs/TROUBLESHOOTING.md'

    switch ($StepName) {
        'git-hygiene' {
            $impact = 'Dirty tree, merge/rebase state, nested clones, or conflict markers can block merges and skew drift checks.'
            $remediation = 'Resolve git state (commit, stash, complete merge/rebase), remove accidental nested clones after review. See docs/TROUBLESHOOTING.md (No Git checkout / Git hygiene).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'bash-syntax' {
            $impact = 'Shell hook scripts are not syntax-checked; Linux CI or contributors may hit runtime shell errors.'
            $remediation = 'Install Git Bash or WSL bash and add to PATH, or run health with an explicit policy skip only where accepted. See docs/TROUBLESHOOTING.md (Bash missing on Windows).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'manifest' {
            $remediation = 'Align bootstrap-manifest.json with templates and repo counts; run pwsh ./tools/verify-bootstrap-manifest.ps1.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'runtime-release' {
            $impact = 'Release metadata (VERSION, os-manifest, ARCHITECTURE/CHANGELOG/SECURITY contract text) is inconsistent.'
            $remediation = 'Sync VERSION with os-manifest.json runtime.version; ensure ARCHITECTURE.md / CHANGELOG.md / SECURITY.md contain required substrings from validationPolicy.releaseContract. See docs/TROUBLESHOOTING.md (ARCHITECTURE / runtime-release mismatch).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'json-contracts' {
            $impact = 'Manifest or config JSON may not match schemas or cross-references; downstream validators may false-green or false-fail.'
            $remediation = 'Run pwsh ./tools/verify-json-contracts.ps1 and fix reported paths; see docs/TROUBLESHOOTING.md (JSON schema failure).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'doctor' {
            $impact = 'Environment or scaffold signals are unhealthy; strict validation escalates doctor warnings.'
            $remediation = 'Run pwsh ./tools/os-doctor.ps1 -Json, address each check, then re-run health. See docs/TROUBLESHOOTING.md.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'skills' {
            $impact = 'Canonical skills, structure, economy, or drift checks failed; project bootstrap may be stale.'
            $remediation = 'Run tools/verify-skills.ps1, verify-skills-structure, sync-skills as appropriate. See docs/TROUBLESHOOTING.md (Skill drift).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'skills-manifest' {
            $remediation = 'Fix skills-manifest.json vs source/skills; run pwsh ./tools/verify-skills-manifest.ps1 -Json. See docs/TROUBLESHOOTING.md (Skill drift).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'agent-adapters' {
            $remediation = 'Run pwsh ./tools/verify-agent-adapters.ps1 and sync templates; see docs/TROUBLESHOOTING.md (Adapter drift).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'doc-contract-consistency' {
            $remediation = 'Align README, manifests, and entrypoints; run pwsh ./tools/verify-doc-contract-consistency.ps1 -Json.'
            $docsLink = 'docs/VALIDATION.md'
        }
        'bootstrap-real-smoke' {
            $remediation = 'Inspect init-project.ps1 logs; ensure bootstrap-manifest projectBootstrap.criticalPaths match template output.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'powershell-syntax' {
            $remediation = 'Fix parse errors in listed scripts; run Parser::ParseFile locally on the reported path.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'preconditions' {
            $impact = 'Health cannot run bash-dependent checks.'
            $remediation = 'Install bash on PATH or omit -RequireBash when local policy allows. See docs/TROUBLESHOOTING.md (Bash missing on Windows).'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'safe-output-lib' {
            $remediation = 'Repair tools/lib/safe-output.ps1; redaction invariants are required for safe JSON output.'
            $docsLink = 'docs/SECURITY.md'
        }
        'runtime-budget' {
            $remediation = 'Fix runtime-budget.json profiles and ordering; run pwsh ./tools/verify-runtime-budget.ps1 -Json.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'context-economy' {
            $remediation = 'Trim CLAUDE.md / AGENTS.md / SKILL files per context-budget.json or relax budgets with governance approval.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'script-manifest' {
            $remediation = 'List every tools/*.ps1 in script-manifest.json or remove stray scripts; run verify-script-manifest.ps1 -Json.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'runtime-profiles' {
            $remediation = 'Repair runtime-profiles.json and tools/runtime-profile.ps1 contract; run verify-runtime-profiles.ps1.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'docs-index' {
            $remediation = 'Sync docs-index.json with docs paths; run verify-docs-index.ps1.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'playbooks' {
            $remediation = 'Fix playbooks and playbook-manifest.json; run verify-playbooks.ps1 -Json.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
        'recipes' {
            $remediation = 'Fix recipes and recipe-manifest.json; run verify-recipes.ps1 -Json.'
            $docsLink = 'docs/TROUBLESHOOTING.md'
        }
    }

    if ($Status -eq 'ok') {
        return [ordered]@{
            reason         = ''
            impact         = ''
            remediation    = ''
            strictImpact   = ''
            docsLink       = ''
        }
    }

    if ($Status -eq 'skip') {
        $strictImpact = 'Skipped steps are not green checks; strict CI usually requires the real step (for example Bash) rather than a permanent skip.'
    }

    return [ordered]@{
        reason       = $reason
        impact       = $impact
        remediation  = $remediation
        strictImpact = $strictImpact
        docsLink     = $docsLink
    }
}

function New-OsDoctorCheckFinding {
    param(
        [string]$CheckName,
        [string]$Status,
        [string]$Detail = ''
    )
    $reason = if (-not [string]::IsNullOrWhiteSpace($Detail)) { $Detail.Trim() } else { "Doctor check '$CheckName' reported '$Status'." }
    $impact = 'Local validation and strict CI may treat this as non-green until resolved.'
    $remediation = 'See docs/TROUBLESHOOTING.md and re-run: pwsh ./tools/os-doctor.ps1 -Json'
    $strictImpact = 'os-validate -Profile strict and verify-os-health -Strict treat unexpected doctor warnings as failures.'
    $docsLink = 'docs/TROUBLESHOOTING.md'

    if ($CheckName -eq 'bash' -and $Status -eq 'warn') {
        $impact = 'Bash syntax checks and hook scripts are skipped or weakened on this machine.'
        $remediation = 'Install Git Bash or WSL, add bash to PATH, then re-run doctor. See docs/TROUBLESHOOTING.md (Bash missing on Windows).'
    }
    elseif ($CheckName -match '^scaffold:' -or $CheckName -eq 'project-scaffold') {
        $remediation = 'For project repos run init-project.ps1 from Claude OS; OS repo may omit .claude intentionally. See docs/TROUBLESHOOTING.md.'
    }
    elseif ($CheckName -eq 'git' -and $Status -eq 'fail') {
        $remediation = 'Install Git for Windows or add git to PATH. See docs/TROUBLESHOOTING.md (No Git checkout).'
    }
    elseif ($CheckName -like 'git:*') {
        $remediation = 'Investigate git lock or performance; retry doctor. See docs/TROUBLESHOOTING.md.'
    }
    elseif ($CheckName -eq 'powershell' -and $Status -eq 'fail') {
        $remediation = 'Install PowerShell 7+ (pwsh) and ensure it is on PATH. See docs/TROUBLESHOOTING.md (PowerShell version mismatch).'
    }
    elseif ($CheckName -eq 'invariant-bundles') {
        $remediation = 'Rebuild templates/invariant-engine bundles (npm run build) or restore dist/*.cjs from a clean checkout.'
        $docsLink = 'docs/TROUBLESHOOTING.md'
    }
    elseif ($CheckName -eq 'node' -or $CheckName -eq 'npm') {
        $impact = 'Invariant engine bundles cannot be rebuilt from source on this machine.'
        $remediation = 'Install Node LTS and npm when maintaining invariant-engine; optional for read-only validation.'
        $docsLink = 'docs/TROUBLESHOOTING.md'
    }

    if ($Status -eq 'ok') {
        return [ordered]@{
            reason         = ''
            impact         = ''
            remediation    = ''
            strictImpact   = ''
            docsLink       = ''
        }
    }

    return [ordered]@{
        reason       = $reason
        impact       = $impact
        remediation  = $remediation
        strictImpact = $strictImpact
        docsLink     = $docsLink
    }
}
