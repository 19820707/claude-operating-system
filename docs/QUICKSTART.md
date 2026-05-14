# Quickstart (about 5 minutes)

## Windows (local-first)

1. Install [PowerShell 7+](https://github.com/PowerShell/PowerShell) (`pwsh`).
2. Clone and enter the repo:

```powershell
git clone https://github.com/19820707/claude-operating-system.git
cd claude-operating-system
```

3. Initialize local runtime context (idempotent; safe to re-run):

```powershell
pwsh ./tools/os-runtime.ps1 init
```

4. Diagnose environment:

```powershell
pwsh ./tools/os-runtime.ps1 doctor
```

5. Run a **quick** validation profile (contracts, budgets, PowerShell syntax — no full health aggregate):

```powershell
pwsh ./tools/os-runtime.ps1 validate -Profile quick -Json
```

If Bash is not on `PATH`, pass `-SkipBashSyntax` on `init` / `doctor` / full health where supported. **Skipped Bash checks are not treated as passed** in strict CI (Ubuntu uses `-RequireBash`).

## Linux / CI (strict path)

On Ubuntu runners, CI runs `os-validate-all.ps1 -Strict -RequireBash` so `bash -n` and Git-backed checks are real gates, not silently skipped.

Local strict profile (includes full `os-validate-all -Strict`):

```powershell
pwsh ./tools/os-validate.ps1 -Profile strict -Json
```

## Project bootstrap

From this repo root:

```powershell
pwsh ./init-project.ps1 ../my-project
```

That copies templates and adapters into the target project. Global install remains `install.ps1` for `~/.claude/`.

## What gets created locally

| Artifact | Purpose |
|----------|---------|
| `OS_WORKSPACE_CONTEXT.md` | Copied from `OS_WORKSPACE_CONTEXT.template.md` once; **gitignored** — local notes only (no secrets). |
| `logs/` | Optional JSONL / logs when tools run with `-WriteHistory` or project scripts write evidence. **gitignored** as a directory. |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `doctor` warns on Bash | Expected on Windows without Git Bash / WSL. Use `-SkipBashSyntax` locally; use Bash on CI for strict. |
| `verify-git-hygiene` warns | Zip / partial copy without `.git` — honest **warn**, not **ok**. |
| Validation **warn** | Not green: do not treat warn/skip/unknown/degraded/blocked as passed. See [VALIDATION.md](VALIDATION.md). |
