# INDEX — claude-operating-system

Navigation map. Every file, its purpose, and when to use it.

---

## Quick reference

| I need to... | Go to |
|-------------|-------|
| Start a new session | `templates/commands/session-start.md` |
| Close a phase | `templates/commands/phase-close.md` |
| Bootstrap a new project | `templates/new-project-bootstrap.md` |
| Restore after machine wipe | `README.md` → Bootstrap section |
| Install on a new machine | `install.ps1` |
| Choose the right model | `policies/model-selection.md` |
| Understand operating modes | `policies/operating-modes.md` |
| Review engineering rules | `policies/engineering-governance.md` |
| Check production safety rules | `policies/production-safety.md` |
| Understand global mandate | `CLAUDE.md` |

---

## Root

| File | Purpose | When to use |
|------|---------|-------------|
| `CLAUDE.md` | Global engineering policy — mandate, session continuity, model selection, discipline | Auto-loaded by Claude Code every session |
| `README.md` | Architecture overview + restore/bootstrap/update procedures | New machine, after format, onboarding |
| `INDEX.md` | This file — navigation map | Whenever you need to find something |
| `install.ps1` | Copies global files to `~/.claude/` | New machine, after format, system update |
| `.gitignore` | Protects secrets and local files from commit | Maintained automatically |

---

## policies/

Binding operational rules. All are loaded via `CLAUDE.md` references.

| File | Purpose | Scope |
|------|---------|-------|
| `model-selection.md` | Task → model matrix (Haiku/Sonnet/Opus); escalation rules; agent→model assignments | All projects |
| `operating-modes.md` | Fast / Phase / Critical / Production mode definitions and transitions | All projects |
| `engineering-governance.md` | Change philosophy; what requires approval; before/after change requirements | All projects |
| `production-safety.md` | What is never autonomous; human gate rules | All projects |

**Gaps (planned):** `token-economy.md`, `reporting-format.md`, `rollback-policy.md`

---

## prompts/

Reusable session prompts. Reference in `.claude/prompts/` of each project.

| File | Purpose | When to use |
|------|---------|-------------|
| `session-start.md` | Read order + session recovery sequence | Start of every session |

**Gaps (planned):** `phase-close.md`, `bootstrap-project.md`, `task-classify.md`, `architecture-review.md`, `release-review.md`, `incident-triage.md`

---

## templates/

Reusable starting points for new projects. Copy and fill in project-specific context.

| File | Purpose | When to use |
|------|---------|-------------|
| `project-CLAUDE.md` | Template for a new project's `CLAUDE.md` | Bootstrapping new project |
| `session-state.md` | Empty template for `.claude/session-state.md` | Bootstrapping new project |
| `learning-log.md` | Empty template for `.claude/learning-log.md` | Bootstrapping new project |
| `new-project-bootstrap.md` | Step-by-step Phase 1/2/3 checklist for new project setup | Bootstrapping new project |

### templates/commands/

Commands to copy into `.claude/commands/` of each project.

| File | Purpose | Trigger |
|------|---------|---------|
| `session-start.md` | Recover full operational context at session start | `/session-start` |
| `phase-close.md` | Capture learning + update state at phase end | `/phase-close` |

**Gaps (planned):** `bootstrap-project.md`, `task-classify.md`

### templates/bootstrap/ *(planned — Fase 7)*

Stack-specific bootstrap guides.

### templates/profiles/ *(planned — Fase 7)*

Per-stack operational profiles: `node-ts-service`, `react-vite-app`, `python-service`, `mono-repo`, etc.

### templates/critical-surfaces/ *(planned — Fase 5)*

Reusable checklists per critical surface: `auth`, `billing`, `migrations`, `deploy`, `pii`, etc.

---

## heuristics/ *(planned — Fase 2)*

Promoted operational patterns from real project evidence.

| Planned file | Content |
|-------------|---------|
| `operational.md` | Environment, git, tooling, Windows-specific patterns |
| `architecture.md` | Boundary, coupling, fail-closed patterns |
| `debugging.md` | Diagnosis, isolation, rollback patterns |
| `token-economy.md` | Context compression, reading discipline |
| `incident.md` | Triage, escalation, recovery patterns |
| `refactoring.md` | Safe change, seam, wiring patterns |

---

## System state

| Component | Status |
|-----------|--------|
| Global CLAUDE.md | Stable |
| install.ps1 | Stable, dry-run validated |
| policies/ | 4/7 — partial |
| prompts/ | 1/7 — partial |
| templates/commands/ | 2/6 — partial |
| heuristics/ | 0 — planned Fase 2 |
| templates/profiles/ | 0 — planned Fase 7 |
| templates/critical-surfaces/ | 0 — planned Fase 5 |
| INDEX.md | This file |

---

## Roadmap summary

| Fase | Objective | Status |
|------|-----------|--------|
| 1 | INDEX.md + navigation | **Done** |
| 2 | Heuristics library in repo | Planned |
| 3 | Policies completion (3 missing) | Planned |
| 4 | Agents + generic commands globalized | Planned |
| 5 | Critical surfaces library | Planned |
| 6 | Prompts expansion | Planned |
| 7 | Stack profiles foundation | Planned |
| 8 | Task modes foundation | Planned |
| 9 | install.sh (Unix) | Planned |
| 10 | Cross-stack validation | Planned |
