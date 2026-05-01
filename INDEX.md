# INDEX — claude-operating-system

Navigation map. Every file, its purpose, and when to use it.

---

## Quick reference

| I need to... | Go to |
|-------------|-------|
| Start a new session | `templates/commands/session-start.md` |
| Close a phase | `templates/commands/phase-close.md` |
| Classify a task | `templates/commands/task-classify.md` |
| Respond to an incident | `templates/commands/incident-triage.md` |
| Review architecture | `templates/commands/architecture-review.md` |
| Bootstrap a new project | `init-project.ps1` (Windows) or `templates/new-project-bootstrap.md` → `/bootstrap-project` |
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
| `install.ps1` | Copies global files to `~/.claude/` on Windows; writes `os-install.json` provenance | New Windows machine, after format |
| `init-project.ps1` | Scaffolds a project path (`-ProjectPath`) or `%USERPROFILE%\claude\<name>\` (`-Name`) with full `.claude/` tree + validation | New app/repo on Windows |
| `bootstrap-manifest.json` | Canonical counts for templates vs CI / `init-project` validation | When adding commands, agents, or critical-surfaces |
| `tools/verify-bootstrap-manifest.ps1` | Fails if repo tree drifts from manifest | CI, local pre-push |
| `install.sh` | Copies global files to `~/.claude/` on Unix/macOS/Linux | New Unix machine, after clone |
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
| `phase-close.md` | Evidence collection + state update + learning capture | End of every phase |
| `bootstrap-project.md` | Phase 1/2/3 bootstrap sequence with exact commands | New project setup |
| `task-classify.md` | Task type + critical surface + model + mode selection | Start of every task |
| `architecture-review.md` | Module map + boundary analysis + structural risk proposals | Architecture work |
| `release-review.md` | Go/no-go report with checks, blockers, rollback | Before any release |
| `incident-triage.md` | Impact scope + evidence + hypothesis + mitigation options | Active incidents |

---

## templates/

Reusable starting points for new projects. Copy and fill in project-specific context.

| File | Purpose | When to use |
|------|---------|-------------|
| `project-CLAUDE.md` | Template for a new project's `CLAUDE.md` (includes @imports) | Bootstrapping new project |
| `session-state.md` | Empty template for `.claude/session-state.md` | Bootstrapping new project |
| `learning-log.md` | Empty template for `.claude/learning-log.md` | Bootstrapping new project |
| `settings.json` | Hook config + approval policy + allow/deny | Bootstrapping new project |
| `new-project-bootstrap.md` | Step-by-step Phase 1/2/3 checklist (includes scripts + hooks) | Bootstrapping new project |

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
| `task-classify.md` | Classify mode/model/blast-radius before any edit | `/task-classify` |
| `incident-triage.md` | Active incident: SEV classification + elite loop | `/incident-triage` |
| `architecture-review.md` | Risk map + top-10 risks + phased plan | `/architecture-review` |
| `bootstrap-project.md` | OS health checklist + restore sequence | `/bootstrap-project` |

### templates/scripts/

Session lifecycle hooks. Copy to `.claude/scripts/` — **must remain LF-only**.

| File | Purpose | Hook |
|------|---------|------|
| `preflight.sh` | Branch/WT/secrets + chama drift + TS budget (warn-only) | `SessionStart` |
| `session-end.sh` | WT snapshot; opcional `OS_STRICT_GATES=1` → gates com `--enforce` | `SessionEnd` |
| `pre-compact.sh` | Extract session-state.md summary before compaction | `PreCompact` |
| `post-compact.sh` | Re-inject context summary after compaction | `PostCompact` |
| `context-drift-detect.sh` | `session-state.md` vs git (branch/HEAD, commits desde doc) | preflight / strict end |
| `ts-error-budget-check.sh` | Compara erros `tsc` ao baseline em `.local/ts-error-budget.json` | preflight / strict end |
| `ts-error-budget-init.sh` | Define `baselineErrors` a partir do `tsc` actual | manual / CI |

### templates/local/

| File | Purpose |
|------|---------|
| `ts-error-budget.json` | Baseline de erros TypeScript (`baselineErrors`, `command`); copiado para `.local/` no init |

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

### templates/task-modes/

Structured workflows per task type. Each defines: model, mode, approval posture, step-by-step sequence, rules, anti-patterns.

| File | Model | When to use |
|------|-------|-------------|
| `bugfix.md` | Sonnet (Opus if critical surface) | Reproducing and fixing a known bug |
| `architecture.md` | Opus always | Mapping structure, boundary changes, structural debt |
| `migration.md` | Opus always | Any schema change — additive, backfill, destructive |
| `incident-response.md` | Opus always | Active production failures, elevated error rates |
| `release-hardening.md` | Opus always | Release candidate validation, go/no-go assessment |

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
| install.sh | Stable, dry-run + real-install validated (bash 5.2 / MSYS2 + Unix-compatible) |
| policies/ | 7/7 — complete |
| prompts/ | 7/7 — complete |
| templates/commands/ | 10/10 — complete |
| templates/scripts/ | 7/7 — hooks + context-drift + ts-error-budget (init/check) |
| templates/settings.json | Stable — 4 hooks + permissions |
| heuristics/ | 1/6 — operational.md done |
| templates/profiles/ | 0 — planned Fase 7 |
| templates/critical-surfaces/ | 5/9 — auth, migrations, billing, deploy, pii |
| templates/task-modes/ | 5/5 — bugfix, architecture, migration, incident-response, release-hardening |
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
| 6 | Prompts expansion | **Done** |
| 7 | Stack profiles foundation | Planned |
| 8 | Task modes foundation | **Done** |
| 9 | install.sh (Unix) | **Done** |
| 10 | Cross-stack validation | Planned |
