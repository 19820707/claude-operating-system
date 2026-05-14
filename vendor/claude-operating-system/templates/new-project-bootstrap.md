# New Project Bootstrap Checklist

Use this checklist when starting a new project with the Claude operational system.
Source: `claude-operating-system/templates/`

---

## Prerequisites

- [ ] `claude-operating-system` cloned locally
- [ ] `install.ps1` already run (global `~/.claude/` configured)
- [ ] Claude Code installed

---

## Phase 1 — Structure

### 1.1 Create project directory
```powershell
git init <project-name>
cd <project-name>
# or: git clone <existing-repo-url> && cd <project-name>
```

### 1.2 Create `.claude/` skeleton
```powershell
mkdir .claude
mkdir .claude\commands
mkdir .claude\scripts
mkdir .claude\policies
mkdir .claude\agents
mkdir .claude\heuristics
```

### 1.3 Copy templates
```powershell
$cos = "C:\Users\<you>\claude-operating-system"

# Core operational files
cp "$cos\templates\project-CLAUDE.md"  CLAUDE.md
cp "$cos\templates\session-state.md"   .claude\session-state.md
cp "$cos\templates\learning-log.md"    .claude\learning-log.md

# Policies (generic — will be extended in Phase 2)
cp "$cos\policies\model-selection.md"        .claude\policies\model-selection.md
cp "$cos\policies\operating-modes.md"        .claude\policies\operating-modes.md
cp "$cos\policies\engineering-governance.md" .claude\policies\engineering-governance.md
cp "$cos\policies\production-safety.md"      .claude\policies\production-safety.md

# Hook scripts (LF-only — copy as-is, do not open in Windows Notepad)
cp "$cos\templates\scripts\preflight.sh"    .claude\scripts\preflight.sh
cp "$cos\templates\scripts\session-end.sh"  .claude\scripts\session-end.sh
cp "$cos\templates\scripts\pre-compact.sh"  .claude\scripts\pre-compact.sh
cp "$cos\templates\scripts\post-compact.sh" .claude\scripts\post-compact.sh
cp "$cos\templates\scripts\drift-detect.sh" .claude\scripts\drift-detect.sh
cp "$cos\templates\scripts\ts-error-budget.sh" .claude\scripts\ts-error-budget.sh
cp "$cos\templates\scripts\heuristic-ratchet.sh" .claude\scripts\heuristic-ratchet.sh
cp "$cos\templates\scripts\promote-heuristics.sh" .claude\scripts\promote-heuristics.sh
cp "$cos\templates\scripts\os-telemetry.sh" .claude\scripts\os-telemetry.sh
mkdir .local 2>nul
cp "$cos\templates\local\ts-error-budget.json" .local\ts-error-budget.json
cp "$cos\templates\local\heuristic-violations.json" .local\heuristic-violations.json
```

- [ ] Templates copied without errors
- [ ] Scripts are LF-only (verify: `Get-Content .claude\scripts\preflight.sh -Raw | Select-String "\r"` returns nothing)

### 1.4 Copy `.claude/settings.json`
```powershell
cp "$cos\templates\settings.json" .claude\settings.json
```
Review and adjust `allow`/`deny` to match your project toolchain.

- [ ] `settings.json` copied and adjusted

### 1.5 Copy all slash commands
```powershell
$cos = "C:\Users\<you>\claude-operating-system"
cp "$cos\templates\commands\*" .claude\commands\
```

Commands included: `session-start`, `session-end`, `phase-close`, `hardening-pass`, `system-review`,
`production-guard`, `release-readiness`, `task-classify`, `incident-triage`,
`architecture-review`, `bootstrap-project`.

Prefer Windows automation: `powershell -ExecutionPolicy Bypass -File <cos>\init-project.ps1 -ProjectPath "%CD%" -Profile node-ts-service`.

- [ ] Commands copied

---

## Phase 2 — Context

### 2.1 Fill in `CLAUDE.md`
Open `CLAUDE.md` and complete:

```markdown
## Project Context
**Stack:** <e.g. Node.js / TypeScript / PostgreSQL>
**Branch model:** <e.g. main / develop>
**Platform:** <e.g. Vercel / AWS / Hostinger>
```

- [ ] Stack filled in
- [ ] Branch model filled in
- [ ] Platform filled in

### 2.2 Define critical surfaces in `CLAUDE.md`
List the specific files that require Opus (auth, billing, publish gates, critical migrations):

```markdown
## Critical Surfaces (Opus mandatory)
- `src/auth/...`
- `src/billing/...`
```

- [ ] Critical surfaces defined (or marked as "none yet" if greenfield)

### 2.3 Extend `model-selection.md` with project-specific surfaces
Open `.claude/policies/model-selection.md` and add a project-specific section at the bottom:

```markdown
## Project-Specific: <project-name>

### OPUS MANDATORY (this project)
- `<path/to/auth-module>`
- `<path/to/billing-module>`
```

- [ ] Project-specific surfaces added

### 2.4 Fill in `session-state.md`
Set initial values:
- Branch: current branch name
- HEAD: first commit hash
- Phase: `Initial setup`
- Objective: `Bootstrap project operational system`
- All other sections: empty or `none`

- [ ] session-state.md initialized

### 2.5 Fill in `learning-log.md`
Add first entry:
```markdown
### Fase Bootstrap — <date>
**Objectivo:** Initialize operational system
**Resultado:** sucesso
**Aprendido:** (fill as project progresses)
```

- [ ] learning-log.md initialized

---

## Phase 3 — Verification

### 3.1 Add `.gitignore` entries
```
.claude/*.tmp
.claude/*.local.json
```

- [ ] `.gitignore` updated

### 3.2 Initial commit
```powershell
git add CLAUDE.md .claude/ .gitignore
git commit -m "ops: bootstrap Claude operational system"
```

- [ ] Commit clean (no secrets, no temp files)
- [ ] `.claude/settings.local.json` NOT committed

### 3.3 Open Claude Code
```powershell
claude
# or use desktop shortcut if configured
```

### 3.4 Run `/session-start`
Type `/session-start` and verify output includes:
- correct branch
- correct HEAD commit
- phase: Initial setup
- no errors reading session-state or learning-log

- [ ] `/session-start` returns clean state

### 3.5 Run `/bootstrap-project` health check
Type `/bootstrap-project` and confirm all OS health items pass.

- [ ] All OS health checks pass

### 3.6 Verify model selection
Ask: "What model should I use for [a task]?" and confirm it follows the policy.

- [ ] Model selection responding correctly

---

## Done

Project is operational. From now on:
- Start every session with `/session-start`
- Close every phase with `/phase-close`
- Update `session-state.md` at the end of each session

---

## Reference

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project context + session continuity + @imports |
| `.claude/session-state.md` | Live operational state (auto-injected) |
| `.claude/learning-log.md` | Cumulative phase learning |
| `.claude/heuristics/operational.md` | Promoted heuristics (auto-injected) |
| `.claude/settings.json` | Approval policy + hooks + allow/deny |
| `.claude/scripts/preflight.sh` | SessionStart hook: branch/WT/secrets check |
| `.claude/scripts/session-end.sh` | SessionEnd hook: WT snapshot |
| `.claude/scripts/pre-compact.sh` | PreCompact hook: extract session summary |
| `.claude/scripts/post-compact.sh` | PostCompact hook: re-inject context |
| `.claude/policies/model-selection.md` | Task → model mapping |
| `.claude/commands/session-start.md` | Session recovery command |
| `.claude/commands/phase-close.md` | Phase close + learning capture |
| `.claude/commands/task-classify.md` | Classify before edit |
| `.claude/commands/incident-triage.md` | Active incident response |
| `.claude/commands/architecture-review.md` | Structural risk map |
| `.claude/commands/bootstrap-project.md` | OS health check + restore |
| `~/.claude/CLAUDE.md` | Global policies (auto-loaded) |
