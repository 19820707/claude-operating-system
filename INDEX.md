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
| `token-economy.md` | Context/token discipline — reading, response, model economy | All sessions |
| `reporting-format.md` | Standard response structure — diagnosis, pre-impl plan, exec result | All responses |
| `rollback-policy.md` | Rollback requirements by change type; anti-patterns; staged rollback | Every change |

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
| `system-review.md` | Full architecture read + risk map + roadmap proposal | `/system-review` |
| `hardening-pass.md` | Low-risk validation/logging/test hardening pass | `/hardening-pass` |
| `production-guard.md` | Confirm approval + rollback before production action | `/production-guard` |
| `release-readiness.md` | Go/no-go assessment with structured report | `/release-readiness` |

**Gaps (planned):** `bootstrap-project.md`, `task-classify.md`

### templates/agents/

Agent definitions to copy into `.claude/agents/` of each project.

| File | Model | Mission |
|------|-------|---------|
| `principal-architect.md` | Opus | Architecture mapping, boundary identification, structural debt |
| `security-engineer.md` | Opus | Auth/authz, trust boundaries, attack surfaces, mitigations |
| `release-manager.md` | Opus | Release readiness, rollback posture, go/no-go evidence |
| `reliability-engineer.md` | Sonnet | Resilience, timeouts, idempotency, failure modes |
| `qa-strategist.md` | Sonnet | Test gaps, regression protection, layered test strategy |

### templates/bootstrap/ *(planned — Fase 7)*

Stack-specific bootstrap guides.

### templates/profiles/ *(planned — Fase 7)*

Per-stack operational profiles: `node-ts-service`, `react-vite-app`, `python-service`, `mono-repo`, etc.

### templates/critical-surfaces/

Reusable reference checklists per critical surface. Copy to `.claude/critical-surfaces/` or reference directly.
All surfaces: **Opus mandatory**, explicit approval required.

| File | Surface | Key risk |
|------|---------|---------|
| `auth.md` | Auth/authz, entitlement engines, trust boundaries | Privilege escalation, bypass, parallel wiring |
| `migrations.md` | Schema migrations — additive vs destructive | Data loss, lock, NOT NULL without default |
| `billing.md` | Payments, subscriptions, webhooks | Double charge, no idempotency, spoofed events |
| `deploy.md` | Production deployments, CI/CD, infra mutations | No rollback, deploy with failures, no approval |
| `pii.md` | Personal data, credentials, sensitive fields | Log leak, URL exposure, real data in tests |

**Gaps (planned):** `integrations.md`, `queues.md`, `agents-runtime.md`, `publish.md`

---

## heuristics/

Promoted operational patterns from real project evidence. Each entry: evidence → rule → how to apply.

| File | Content | Status |
|------|---------|--------|
| `operational.md` | Environment, git, Windows tooling, security validation, architecture patterns (H1–H10) | **Done** |
| `architecture.md` | Boundary, coupling, fail-closed, interface patterns | Planned Fase 3+ |
| `debugging.md` | Diagnosis, isolation, rollback patterns | Planned |
| `token-economy.md` | Context compression, reading discipline | Planned Fase 3 |
| `incident.md` | Triage, escalation, recovery patterns | Planned |
| `refactoring.md` | Safe change, seam, wiring patterns | Planned |

---

## System state

| Component | Status |
|-----------|--------|
| Global CLAUDE.md | Stable |
| install.ps1 | Stable, dry-run validated |
| policies/ | 7/7 — complete |
| prompts/ | 1/7 — partial |
| templates/commands/ | 6/6 — complete |
| heuristics/ | 1/6 — operational.md done |
| templates/profiles/ | 0 — planned Fase 7 |
| templates/critical-surfaces/ | 5/9 — auth, migrations, billing, deploy, pii |
| INDEX.md | This file |

---

## Roadmap summary

| Fase | Objective | Status |
|------|-----------|--------|
| 1 | INDEX.md + navigation | **Done** |
| 2 | Heuristics library in repo | **Done** |
| 3 | Policies completion (3 missing) | **Done** |
| 4 | Agents + generic commands globalized | **Done** |
| 5 | Critical surfaces library (5 core) | **Done** |
| 6 | Prompts expansion | Planned |
| 7 | Stack profiles foundation | Planned |
| 8 | Task modes foundation | Planned |
| 9 | install.sh (Unix) | Planned |
| 10 | Cross-stack validation | Planned |
