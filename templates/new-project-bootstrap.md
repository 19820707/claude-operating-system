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
mkdir .claude\policies
mkdir .claude\agents
```

### 1.3 Copy templates
```powershell
$cos = "C:\Users\pqjs2\claude-operating-system"

# Core operational files
cp "$cos\templates\project-CLAUDE.md"  CLAUDE.md
cp "$cos\templates\session-state.md"   .claude\session-state.md
cp "$cos\templates\learning-log.md"    .claude\learning-log.md

# Policies (generic — will be extended in Phase 2)
cp "$cos\policies\model-selection.md"       .claude\policies\model-selection.md
cp "$cos\policies\operating-modes.md"       .claude\policies\operating-modes.md
cp "$cos\policies\engineering-governance.md" .claude\policies\engineering-governance.md
cp "$cos\policies\production-safety.md"     .claude\policies\production-safety.md

# Commands
cp "$cos\prompts\session-start.md" .claude\prompts\session-start.md
```

- [ ] Templates copied without errors

### 1.4 Create `.claude/settings.json`
```json
{
  "approvalPolicy": "on-request",
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(npm run typecheck *)",
      "Bash(npm run test:unit *)",
      "Bash(npx vitest run *)"
    ],
    "deny": [
      "Bash(git push --force *)",
      "Bash(git reset --hard *)",
      "Bash(rm -rf *)"
    ]
  }
}
```
Adjust allow/deny to match project toolchain.

- [ ] `settings.json` created

### 1.5 Create `/session-start` and `/phase-close` commands
```powershell
$cos = "C:\Users\pqjs2\claude-operating-system"
# Copy from a project that already has them (e.g. Rallyo):
$rallyo = "D:\Rallyos\Rallyo-Platform"
cp "$rallyo\.claude\commands\session-start.md" .claude\commands\session-start.md
cp "$rallyo\.claude\commands\phase-close.md"   .claude\commands\phase-close.md
```

- [ ] Commands created

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

### 3.1 Initial commit
```powershell
git add CLAUDE.md .claude/
git commit -m "ops: bootstrap Claude operational system"
```

- [ ] Commit clean (no secrets, no temp files)
- [ ] `.claude/settings.local.json` NOT committed

### 3.2 Open Claude Code
```powershell
claude
# or use desktop shortcut if configured
```

### 3.3 Run `/session-start`
Type `/session-start` and verify output includes:
- correct branch
- correct HEAD commit
- phase: Initial setup
- no errors reading session-state or learning-log

- [ ] `/session-start` returns clean state

### 3.4 Verify model selection
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
| `CLAUDE.md` | Project context + session continuity instructions |
| `.claude/session-state.md` | Live operational state |
| `.claude/learning-log.md` | Cumulative phase learning |
| `.claude/policies/model-selection.md` | Task → model mapping |
| `.claude/commands/session-start.md` | Session recovery command |
| `.claude/commands/phase-close.md` | Phase close + learning capture |
| `~/.claude/CLAUDE.md` | Global policies (auto-loaded) |
