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
