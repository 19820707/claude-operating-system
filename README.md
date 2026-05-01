# claude-operating-system

Source of truth for global Claude Code operational infrastructure.
Persistent, versionable, restorable across machines and projects.

**Navigation:** see [INDEX.md](INDEX.md) for a full map of every file and when to use it.

---

## Architecture

```
claude-operating-system/          ← this repo (global source of truth)
├── CLAUDE.md                     ← global engineering policy
├── install.ps1                   ← bootstrap script for new machine
├── init-project.ps1              ← scaffold a new project (Windows)
├── policies/                     ← global policies (generic, no project paths)
├── prompts/                      ← global prompts
└── templates/                    ← bootstrap templates for new projects

~/.claude/                        ← active local copy (reconstructible)
├── CLAUDE.md                     ← copied from this repo by install.ps1
├── policies/                     ← copied from this repo
├── prompts/                      ← copied from this repo
├── settings.json                 ← local only (not in this repo)
└── projects/                     ← runtime memory per project

<each-project-repo>/              ← project-specific context (inside the repo)
├── CLAUDE.md                     ← project context (extends global)
└── .claude/
    ├── session-state.md          ← live operational state
    ├── learning-log.md           ← cumulative phase learning
    ├── commands/                 ← /session-start, /phase-close, etc.
    ├── agents/                   ← project agents
    └── policies/                 ← project-specific policy overrides
```

**Key principle:** `~/.claude/` is disposable. Everything important lives either here (global) or inside project repos.

### Advanced engineering (project hooks)

Templates ship **proactive** checks, not only policy text:

- **Context drift** — `templates/scripts/context-drift-detect.sh` compares the **Identificação** table in `.claude/session-state.md` to live `git` (branch, HEAD, commits after the documented SHA). Invoked from `preflight.sh` (warn-only). Set **`OS_STRICT_GATES=1`** so `session-end.sh` runs the same scripts with **`--enforce`** and blocks the hook on drift or TS regression.
- **TypeScript error budget** — `.local/ts-error-budget.json` (template under `templates/local/`) holds `baselineErrors` and the `tsc` command. Run **`bash .claude/scripts/ts-error-budget-init.sh`** once to capture the baseline; each session **`ts-error-budget-check.sh`** warns if errors increased above baseline.

---

## Bootstrap a new machine

```powershell
# 1. Install Claude Code
# https://claude.ai/download

# 2. Clone this repo
git clone https://github.com/<user>/claude-operating-system
cd claude-operating-system

# 3. Install global config
powershell -ExecutionPolicy Bypass -File install.ps1

# 4. Clone each project repo
git clone https://github.com/<user>/<project-repo>

# 5. Open Claude Code in project directory
# cd <project-repo> && claude

# 6. Recover session context
# Type: /session-start
```

---

## Restore after crash or full format

Same as bootstrap above. All context is preserved because:
- Global policies → this repo
- Project state (`session-state.md`, `learning-log.md`, commands, agents) → inside each project repo
- `~/.claude/settings.json` → recreate manually (approval policies, permissions)

Estimated restore time: ~5 minutes per machine.

---

## Update the global system

```powershell
# Edit files in this repo (CLAUDE.md, policies/, etc.)
# Then re-run install.ps1 to sync to ~/.claude/
powershell -ExecutionPolicy Bypass -File install.ps1

# Commit and push
git add -A
git commit -m "update: <what changed>"
git push
```

---

## Start a new project

**Fast path (Windows):** from your `claude-operating-system` clone:

```powershell
cd <path-to>\claude-operating-system
powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -ProjectPath "$env:USERPROFILE\claude\my-new-project"
cd $env:USERPROFILE\claude\my-new-project
claude
# Type: /session-start
```

Or a short name under `%USERPROFILE%\claude\`:

```powershell
powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -Name my-new-project
```

Creates `CLAUDE.md`, `.claude/` (session-state, learning-log, settings, policies, commands, agents, critical-surfaces, heuristics, scripts), runs `git init`, validates counts (10 commands, 5 agents, 5 critical surfaces), and appends minimal `.gitignore` rules. **Protected:** `session-state.md` and `learning-log.md` are never overwritten if they already exist. **CLAUDE.md** is skipped when present unless `-Force`. Use `-DryRun` to preview. See `templates/new-project-bootstrap.md` for the full manual checklist.

**Manual path (any OS):**

```powershell
# 1. Create project repo
git init my-new-project && cd my-new-project

# 2. Copy templates
mkdir .claude
cp <path-to>/claude-operating-system/templates/session-state.md .claude/session-state.md
cp <path-to>/claude-operating-system/templates/learning-log.md .claude/learning-log.md
cp <path-to>/claude-operating-system/templates/project-CLAUDE.md CLAUDE.md

# 3. Fill in project context in CLAUDE.md
# 4. Open Claude Code: claude
# 5. Type /session-start
```

---

## How to use /session-start

Type `/session-start` at the beginning of every Claude Code session.

Claude will read:
1. `~/.claude/CLAUDE.md` — global policies
2. `CLAUDE.md` — project context
3. `.claude/session-state.md` — current branch, decisions, risks, next steps
4. `.claude/learning-log.md` — active heuristics and anti-patterns

Response format:
```
SESSÃO RECUPERADA
Branch: <branch>
HEAD: <commit>
Fase: <current phase>
Próximo passo: <minimum action>
Riscos: <active risks>
```

---

## How to use /phase-close

Type `/phase-close` at the end of each work phase.

Claude will:
1. Update `.claude/session-state.md` with current state
2. Append to `.claude/learning-log.md`: learned / failed / new rules / avoid / next step
3. Promote new heuristics if confirmed
4. Confirm checks and rollback

---

## How to close a session correctly

At the end of each session, say:
> "Fecha a sessão e actualiza o session-state"

Claude updates `.claude/session-state.md` with the real state.
On the next session, `/session-start` recovers everything.

---

## Rollback

This repo only adds files — it never modifies existing project repos or deletes anything.

To undo the install:
```powershell
# Remove installed files from ~/.claude/
rm "$env:USERPROFILE\.claude\CLAUDE.md"
rm -r "$env:USERPROFILE\.claude\policies"
rm -r "$env:USERPROFILE\.claude\prompts"
# settings.json and projects/ are untouched
```

To remove this repo entirely:
```powershell
rm -rf C:\Users\pqjs2\claude-operating-system
```

---

## What stays local (never commit)

- `~/.claude/settings.json` — approval policies, tool permissions
- `~/.claude/settings.local.json` — local overrides
- `~/.claude/projects/` — runtime memory (regenerated automatically)
- `.env`, secrets, credentials — never anywhere near this repo
