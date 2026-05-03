# claude-operating-system

Source of truth for global Claude Code operational infrastructure.
Persistent, versionable, restorable across machines and projects.

Claude OS is **operational governance for agents over the repo** (contracts, validation, context, capabilities, auditability)—**not** a replacement for CI/CD, Actions, or human release gates. It sits between tool-native agents and formal delivery systems to **improve inputs** upstream of them. See [ARCHITECTURE.md — Operational positioning](ARCHITECTURE.md#operational-positioning), [What Claude OS is not](ARCHITECTURE.md#what-claude-os-is-not) (English), [docs/POSICIONAMENTO-NAO-E.md](docs/POSICIONAMENTO-NAO-E.md) (PT), and [docs/CAPACIDADES-OPERACIONAIS.md](docs/CAPACIDADES-OPERACIONAIS.md) (PT — fluxo §2–§11; competências §14; maturidade §15; resultado §16; autonomia A0–A4 §17).

**Navigation:** see [INDEX.md](INDEX.md) for a full map of every file and when to use it. Quick paths: **[docs/QUICKSTART.md](docs/QUICKSTART.md)**, **[docs/VALIDATION.md](docs/VALIDATION.md)**, **[docs/AUTONOMY.md](docs/AUTONOMY.md)** (autonomy / `os-autopilot`), **[docs/RELEASE-READINESS.md](docs/RELEASE-READINESS.md)**, **[docs/SKILLS.md](docs/SKILLS.md)** (skills), **[playbooks/README.md](playbooks/README.md)** (playbooks), **[recipes/README.md](recipes/README.md)** (command recipes + `recipe-manifest.json`).

---

## Get started

```powershell
git clone https://github.com/19820707/claude-operating-system.git
cd claude-operating-system
pwsh ./tools/os-runtime.ps1 init
pwsh ./tools/os-runtime.ps1 doctor
pwsh ./tools/os-runtime.ps1 validate -Profile quick
```

Strict validation (release-style, includes full `os-validate-all` when profile is `strict`):

```powershell
pwsh ./tools/os-runtime.ps1 validate -Profile strict -Json
```

Scaffold a new project (from this repo):

```powershell
pwsh ./init-project.ps1 ../my-project
```

**Surfaces:** This repository is the **global source** for policies and templates. **`~/.claude/`** is the active local copy after `install.ps1` (disposable; reconstructible). Each **project repo** carries its own `.claude/` runtime (session state, learning log, commands) plus thin adapters (`AGENTS.md`, `.cursor/rules/`, etc.).

**Profiles:** **quick** runs contracts, **skills manifest + structure + `verify-skills`**, and lightweight verifiers. **standard** adds **skills economy + drift** (warn on body drift if copies exist), manifests, adapter checks, Git hygiene (warn if not a Git checkout), and `os-doctor`. **strict** uses **`-Strict`** on skills manifest/structure/drift (missing generated copies and manifest disk mismatches fail), then `os-validate-all -Strict` (bootstrap smoke, session cycle, bash `-n` when Bash is on PATH and not skipped).

**Bash:** Optional on Windows for local runs (`-SkipBashSyntax`). **CI (Ubuntu)** uses `-RequireBash` so shell syntax is a real gate.

**Honest status:** `warn`, `skip`, `unknown`, `degraded`, `blocked`, and `not_run` are **not** treated as passed (see `runtime-budget.json` / [VALIDATION.md](docs/VALIDATION.md)).

**Evidence:** Use `-WriteHistory` on `init`, `validate`, `verify-os-health`, or `os-validate-all` to append one JSON object per run to `logs/validation-history.jsonl` (gitignored).

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

**Session pipeline (economy + validation):** work follows **prime → absorb → execute → verify → export** — explicit stages, JSON/schema checks before trust, incremental indexes (`session-index.json`). Same engineering stance as [graphify](https://github.com/safishamsi/graphify) (staged pipeline, validate-before-consume). Details: **[ARCHITECTURE.md](ARCHITECTURE.md)** (graphify-aligned section + **Claude OS Runtime** contract).

### Multi-tool projects (Claude Code, Cursor, Codex)

Use **one operational tree per project** (`.claude/`) and **thin tool adapters** at the repo root (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, optional `.agent/`). Avoid parallel “OS” directories or three full copies of the same policies — see [policies/multi-tool-adapters.md](policies/multi-tool-adapters.md). The adapter map in this repo is **`agent-adapters-manifest.json`** (schema **`schemas/agent-adapters.schema.json`**); validate with **`pwsh ./tools/verify-agent-adapters.ps1`**.

### Advanced engineering (project hooks)

Templates ship **proactive** checks, not only policy text:

- **Context drift** — `templates/scripts/drift-detect.sh` compares the **Identificação** table in `.claude/session-state.md` to live `git`, logs `.claude/drift.log`, and warns on stale state / WT growth. Invoked from `preflight.sh` (always `exit 0`).
- **TypeScript error budget** — `templates/scripts/ts-error-budget.sh` + `.local/ts-error-budget.json` (`baseline`, `ts`, `reset_by`). Auto-inits baseline; **`--enforce`** exits non-zero on regression; **`--reset`** sets a new baseline.
- **Heuristic ratchet** — `heuristic-ratchet.sh` tracks H1/H5/H10 counts in `.local/heuristic-violations.json` with **`--enforce`** / **`--reset`**.
- **Telemetry** — `os-telemetry.sh` maintains `.claude/os-metrics.json`; SessionEnd runs it after `session-end.sh`. Use **`--report`** to print metrics without incrementing `sessions`.

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
powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -ProjectPath "$env:USERPROFILE\claude\my-new-project" -Profile node-ts-service
cd $env:USERPROFILE\claude\my-new-project
claude
# Type: /session-start
```

Creates `CLAUDE.md`, `.claude/` (commands, agents, OS `policies/*.md` + critical-surface checklists into `.claude/policies/`, scripts including drift/TS budget/heuristic ratchet/telemetry/promotion, heuristics), `.local/` (TS + ratchet JSON), runs `git init`, validates **12** critical paths, and appends `.gitignore` rules (`.local/`, `.claude/*.tmp`, `.claude/os-metrics.json`). **Protected:** `session-state.md`, `learning-log.md`, `settings.json`, local JSONs — never overwritten if present. **CLAUDE.md** unless `-Force`. Optional `-Profile node-ts-service` or `react-vite-app` → `.claude/stack-profile.md`. See `templates/new-project-bootstrap.md` for the full manual checklist.

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
