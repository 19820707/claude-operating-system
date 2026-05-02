# INDEX — claude-operating-system

Navigation map. Every file, its purpose, and when to use it.

---

## Quick reference

| I need to... | Go to |
|-------------|-------|
| Check full OS health | `pwsh ./tools/verify-os-health.ps1` (optional **`-Json`**; redirect stderr with **`2>$null`** when piping JSON only) |
| Release aggregate validation | `pwsh ./tools/os-validate-all.ps1 -Strict` (optional **`-Json`**) |
| Check Git workspace hygiene (read-only) | `pwsh ./tools/verify-git-hygiene.ps1` |
| Verify multi-agent adapter templates + manifest | `pwsh ./tools/verify-agent-adapters.ps1` (optional `-Json`) |
| Recover from fetch/rebase/nested clone issues | `GIT-RECOVERY.md` (also `docs/GIT-RECOVERY.md`) |
| Start a new session | `templates/commands/session-start.md` |
| Close a phase | `templates/commands/phase-close.md` |
| Classify a task | `templates/commands/task-classify.md` |
| Respond to an incident | `templates/commands/incident-triage.md` |
| Review architecture | `templates/commands/architecture-review.md` |
| Bootstrap a new project | `init-project.ps1 -ProjectPath …` (Windows) or `templates/new-project-bootstrap.md` → `/bootstrap-project` |
| Restore after machine wipe | `README.md` → Bootstrap section |
| Install on a new machine | `install.ps1` |
| Choose the right model | `policies/model-selection.md` |
| Understand operating modes | `policies/operating-modes.md` |
| Review engineering rules | `policies/engineering-governance.md` |
| Same repo, Claude + Cursor + Codex | `policies/multi-tool-adapters.md` |
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
| `init-project.ps1` | Scaffolds `-ProjectPath` (mandatory), optional `-Profile`, manifest-driven validation | New app/repo on Windows |
| `bootstrap-manifest.json` | Canonical counts, skills, project bootstrap script list, and critical-path list for CI drift detection | When adding skills, commands, agents, profiles, scripts, or bootstrap critical paths |
| `tools/verify-os-health.ps1` | Aggregates manifest, skills, docs, syntax, real bootstrap smoke, Bash checks, safe-output probe, **git-hygiene**, dispatcher checks, **doctor** (soft **10s** / hard **30s** latency budgets); **`-Json`** emits a compact envelope and uses **process exit codes** (`0` ok/warn-only, `1` fail / strict blocked); **`-Strict`** matches `os-validate-all -Strict` and fails on disallowed warnings (for example doctor soft-budget) | Primary local and CI health check |
| `tools/os-validate-all.ps1` | Release gate: health, doctor (strict rules), json-contracts, generated project tools, session-memory cycle; **`-Json`** emits compact summary plus optional **healthSummary** (status, failure/warning counts, totalMs) | CI / pre-push |
| `tools/verify-git-hygiene.ps1` | Read-only: nested `claude-operating-system/`, nested `.git`, rebase/merge/cherry state, conflict markers (`<<<<<<<` / `=======` / `>>>>>>>`), dirty tree; **`-Strict`** or CI = nested clone **FAIL**; **`-Strict`** also elevates remaining hygiene warnings to failures; optional **`-Json`** includes `checks`, `failureCount`, `warningCount` | Before `git add`, CI, release |
| `tools/verify-runtime-dispatcher.ps1` | Contract tests for `tools/os-runtime.ps1` (help, JSON routes, absorb/digest guardrails) | Invoked from health |
| `GIT-RECOVERY.md` | Safe Git recovery — fetch first, rebase conflicts, nested clone, stash discipline, forbidden commands | When push/pull/rebase fails |
| `tools/verify-bootstrap-manifest.ps1` | Fails if repo tree or project bootstrap lists drift from manifest | CI, local pre-push, health check component |
| `tools/verify-skills.ps1` | Fails if `source/skills/*/SKILL.md` frontmatter, categories, links, or counts drift from manifest | CI, local pre-push, health check component |
| `tools/verify-doc-manifest.ps1` | Fails if INDEX.md summary drifts from manifest counts | CI, local pre-push, health check component |
| `install.sh` | Copies global files to `~/.claude/` on Unix/macOS/Linux | New Unix machine, after clone |
| `.gitignore` | Protects secrets and local files from commit | Maintained automatically |

---

## source/skills/

Canonical skill layer. `source/skills` is source of truth; `init-project.ps1` installs it into `.claude/skills/`.
Canonical count: **6/6** from `bootstrap-manifest.json`.

| Skill | Category | Purpose |
|-------|----------|---------|
| `bootstrap-governance` | governance | Bootstrap, manifests, scripts, critical paths, drift detection |
| `production-safety` | safety | Auth, billing, PII, deploy, rollback, approval gates |
| `token-economy` | economy | Context minimization, cheap checks, proportional validation |
| `invariant-engineering` | verification | Invariants, semantic diff, contract deltas, verification gates |
| `multi-agent-coordination` | coordination | Leases, intentions, shared decisions, collision prevention |
| `epistemic-discipline` | verification | KNOWN / INFERRED / ASSUMED / DISPUTED / UNKNOWN discipline |

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
| `multi-tool-adapters.md` | One `.claude/` runtime + thin adapters (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, `.agent/`) — avoid drift | Multi-tool teams |

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

Commands to copy into `.claude/commands/` of each project. Canonical count: **18/18** from `bootstrap-manifest.json`.

| File | Purpose | Trigger |
|------|---------|---------|
| `session-start.md` | Recover full operational context at session start | `/session-start` |
| `phase-close.md` | Capture learning + update state at phase end | `/phase-close` |
| `session-end.md` | Close session with final state and evidence capture | `/session-end` |
| `system-review.md` | Full architecture read + risk map + roadmap proposal | `/system-review` |
| `hardening-pass.md` | Low-risk validation/logging/test hardening pass | `/hardening-pass` |
| `production-guard.md` | Confirm approval + rollback before production action | `/production-guard` |
| `release-readiness.md` | Go/no-go assessment with structured report | `/release-readiness` |
| `task-classify.md` | Classify mode/model/blast-radius before any edit | `/task-classify` |
| `incident-triage.md` | Active incident: SEV classification + elite loop | `/incident-triage` |
| `architecture-review.md` | Risk map + top-10 risks + phased plan | `/architecture-review` |
| `bootstrap-project.md` | OS health checklist + restore sequence | `/bootstrap-project` |
| `claim-module.md` | Claim coordination lease before editing shared surfaces | `/claim-module` |
| `release-module.md` | Release a coordination lease after completing work | `/release-module` |
| `audit-session.md` | Audit decision log and operational compliance | `/audit-session` |
| `verify-invariants.md` | Run or review invariant verification evidence | `/verify-invariants` |
| `epistemic-review.md` | Review assumptions, unknowns, and decision debt | `/epistemic-review` |
| `simulate.md` | Simulate change impact before applying risky edits | `/simulate` |
| `consolidate.md` | Consolidate session evidence into runbooks/state | `/consolidate` |

### templates/scripts/

Session lifecycle hooks. Copy to `.claude/scripts/` — **must remain LF-only**. Canonical count: **38/38** from `bootstrap-manifest.json`; `init-project.ps1` consumes that manifest list directly.

| File | Purpose | Hook |
|------|---------|------|
| `preflight.sh` | drift, ratchet, TS budget, **risk-surface-scan**, **living-arch-graph** (`LIVING_ARCH_SKIP=1`), **invariant-verify** (`INVARIANT_VERIFY=1`), **invariant-lifecycle** (`INVARIANT_LIFECYCLE=1`, `INVARIANT_LIFECYCLE_FOR=`), **coordination-check** (`COORDINATION_CHECK=1`, `COORDINATION_SESSION=`, `COORDINATION_WT=`), **epistemic-check** (`EPISTEMIC_CHECK=1`, `EPISTEMIC_PLAN_DEPENDS=`), **risk-model** (`RISK_MODEL=1`+target), **semantic-diff** (`SEMANTIC_DIFF=1`+target), **learning-loop** (`LEARNING_LOOP=1`), **policy-compliance-audit** (`POLICY_AUDIT=1`), **context-topology** (`CONTEXT_TOPOLOGY=1`, `CONTEXT_TOPOLOGY_FOR=`), telemetria | `SessionStart` |
| `session-end.sh` | WT snapshot (`wt-snapshot.tmp`) | `SessionEnd` (antes de `os-telemetry.sh` na cadeia) |
| `pre-compact.sh` | Extract session-state.md summary before compaction | `PreCompact` |
| `post-compact.sh` | Re-inject context summary after compaction | `PostCompact` |
| `drift-detect.sh` | `session-state` vs git, `drift.log`, stale / WT | `preflight` |
| `ts-error-budget.sh` | Baseline `tsc` em `.local/ts-error-budget.json` | `preflight` |
| `heuristic-ratchet.sh` | H1/H5/H10 → `.local/heuristic-violations.json` | `preflight` |
| `promote-heuristics.sh` | learning-log YAML → `operational.md` (`--promote`) | manual |
| `os-telemetry.sh` | `.claude/os-metrics.json` (`--report` só leitura) | `preflight` + `SessionEnd` |
| `risk-surface-scan.sh` | Walk do repo + padrões vs `CLAUDE.md` Critical Surfaces → `.claude/risk-surfaces.json` | `preflight` (após TS budget) |
| `module-complexity.sh` | Score git (90d) por ficheiro; `--scan` + `.claude/complexity-map.json` | `/task-classify` |
| `causal-trace.sh` | `--file` / `--commit` / `--incident` vs `session-index.json` | post-mortem |
| `session-index.sh` | Parse `session-state.md` → `session-index.json`; `--query <módulo>` | `/phase-close` |
| `cross-project-sync.sh` | `--contribute` / `--inherit` / `--report` vs OS `heuristics/cross-project-evidence.json` | `/phase-close` + init (doc) |
| `living-arch-graph.sh` | Grafo de imports real (`server/`, `client/`, `shared/`, `src/`) → `.claude/architecture-graph.json`; `--blast-radius <ficheiro>`; violações vs `.claude/architecture-boundaries.json` | `preflight` + `/task-classify` |
| `invariant-verify.sh` | Arranca motor empacotado **TypeScript Compiler API** → `.claude/invariant-report.json`; specs `.claude/invariants/*.json` | manual ou `INVARIANT_VERIFY=1` no preflight |
| `probabilistic-risk-model.sh` | P(incident), P(regression condicionado a coverage, blast esperado (git 180d + grafo opcional) → `.claude/risk-model.json` | `/task-classify` ou `RISK_MODEL=1` + `RISK_MODEL_TARGET` |
| `semantic-diff-analyze.sh` | Diff semântico TS: contratos exportados, heurística de refactor, padrões de risco (ex. role → roles) → `.claude/semantic-diff-report.json` | `/task-classify` ou `SEMANTIC_DIFF=1` + `SEMANTIC_DIFF_TARGET` |
| `autonomous-learning-loop.sh` | Anomalias (sessões + git revert) → hipóteses `H-AUTO-*` → rascunho de política; relatório `.claude/learning-loop-report.json` — **gate humano** antes de `operational.md` | `/phase-close` / manual / `LEARNING_LOOP=1` |
| `decision-append.sh` | Append **uma** linha JSON a `.claude/decision-log.jsonl` (trilho de decisão verificável) | antes de actuar / automação |
| `policy-compliance-audit.sh` | Lê `decision-log.jsonl` → `[OS-AUDIT]` + taxa de compliance + aviso de **drift** se abaixo de 85% (com volume mínimo) | `POLICY_AUDIT=1` / manual |
| `context-topology.sh` | Gera/atualiza `.claude/knowledge-graph.json`; `--inject <ficheiro>`; `--budget [--for path]` | `CONTEXT_TOPOLOGY=1` / manual |
| `invariant-lifecycle.sh` | Registo temporal `.claude/invariants.json`: **staleness** (git após `last_verified`), **obsolescence_probe**, **genealogy**; `--for path`; `--apply` persiste `STALE` | `INVARIANT_LIFECYCLE=1` / manual |
| `coordination-check.sh` | Multi-agente: **leases** / **intentions** / **shared_decisions** em `.claude/agent-state.json` vs paths (`--paths`, `COORDINATION_PATHS`, ou `COORDINATION_WT=1`) | `COORDINATION_CHECK=1` / manual |
| `epistemic-check.sh` | **KNOWN/INFERRED/ASSUMED/DISPUTED** em `.claude/epistemic-state.json`; `--summary`; `--gate --depends`; `--score-decision`; `--score-all`; `--decision-debt` | `EPISTEMIC_CHECK=1` / manual |

For the complete script list, use `bootstrap-manifest.json` → `projectBootstrap.scripts`; CI verifies every listed script exists and parses with `bash -n`.

Manifest-only script entries: `agent-coordinator.sh`, `consolidate-runbook.sh`, `context-allocator.sh`, `context-builder.sh`, `contract-delta.sh`, `decision-audit.sh`, `epistemic-state.sh`, `invariant-engine.sh`, `knowledge-graph.sh`, `policy-compliance.sh`, `runbook-inject.sh`, `salience-score.sh`, `simulate-change.sh`.

### templates/invariant-engine/

| Artefacto | Propósito |
|-----------|-----------|
| `src/invariant-engine.ts` | Motor invariantes — `pattern_count`, `fail_closed_switch`, `sensitive_logger`, `missing_pattern` |
| `src/semantic-diff.ts` | Analisador de diff semântico (contratos AST + heurísticas) |
| `dist/invariant-engine.cjs` | Bundle esbuild — copiado no init |
| `dist/semantic-diff.cjs` | Bundle esbuild — copiado no init |
| `dist/simulate-contract-delta.cjs` | Bundle esbuild — simulação de delta contratual copiada no init |
| `package.json` | `npm run build` — gera os bundles `.cjs` |

### templates/local/

| File | Purpose |
|------|---------|
| `ts-error-budget.json` | Schema `baseline` / `ts` / `reset_by` — copiado para `.local/` |
| `heuristic-violations.json` | Baseline H1/H5/H10 — copiado para `.local/` |
| `architecture-boundaries.json` | Regras `from_prefix` → `to_prefix` para deteção de violações de camada — copiado para `.claude/` (se ausente) |
| `invariants/default.json` | Pack exemplo INV-001…004 — copiado para `.claude/invariants/` (se ausente) |
| `learning-loop-state.json` | Contador `H-AUTO-NNN` para o loop autónomo — copiado para `.claude/` (se ausente) |
| `decision-log.schema.json` | Schema JSON das entradas do **decision log** — referência em `.claude/` (se ausente) |
| `knowledge-graph.seed.json` | Shell inicial do **grafo de conhecimento** → `.claude/knowledge-graph.json` (se ausente) |
| `invariants-registry.seed.json` | Registo de invariantes com ciclo de vida → `.claude/invariants.json` (se ausente); complementa `.claude/invariants/*.json` do motor AST |
| `agent-state.seed.json` | Coordenação multi-sessão → `.claude/agent-state.json` (leases, intentions, shared_decisions) |
| `epistemic-state.seed.json` | Factos + `unknown_required` → `.claude/epistemic-state.json` (modelo epistémico) |

### templates/profiles/

| File | Stack |
|------|--------|
| `node-ts-service.md` | Node + TS + Express/Fastify + PostgreSQL |
| `react-vite-app.md` | React 18 + Vite + TS + Tailwind |

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

Reusable reference checklists per critical surface. `init-project.ps1` copies these into `.claude/policies/` alongside global policy markdown.
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
| `cross-project-evidence.json` | Evidência central (patterns); `cross-project-sync.sh` actualiza | **MVP** |
| `architecture.md` | Boundary, coupling, fail-closed, interface patterns | Planned Fase 3+ |
| `debugging.md` | Diagnosis, isolation, rollback patterns | Planned |
| `token-economy.md` | Context compression, reading discipline | Planned Fase 3 |
| `incident.md` | Triage, escalation, recovery patterns | Planned |
| `refactoring.md` | Safe change, seam, wiring patterns | Planned |

---

## Multi-agent adapters

Thin adapters for **Claude Code**, **Cursor**, and **Codex / generic agents** against the **same** operational runtime **`.claude/`**. Templates live under **`templates/adapters/`**; **`init-project.ps1`** installs them into a new project (**`AGENTS.md`** and **`CLAUDE.md`** are skipped when already present — use **`-Force`** to replace from templates); **`tools/os-update-project.ps1`** refreshes managed files without overwriting an existing **`AGENTS.md`**.

| Artifact | Role |
|----------|------|
| **`AGENTS.md`** (project root) | Codex / generic contract — read order, scripts, git safety |
| **`.cursor/rules/claude-os-runtime.mdc`** | Cursor Project Rules (`alwaysApply: true`) |
| **`.agent/runtime.md`** | Neutral map: what `.claude/` is vs adapters |
| **`.agent/handoff.md`** | Prime → absorb → digest; update session-state |
| **`.agent/operating-contract.md`** | local-first, artifact-first, no secrets, git rules, validate before close |
| **`.agents/OPERATING_CONTRACT.md`** | Legacy path (some templates): thin pointer → `.agent/operating-contract.md` — not a parallel runtime |
| **`agent-adapters-manifest.json`** | Declares consumers (`claude-code`, `cursor`, `codex`, `neutral-agent-docs`) |
| **`schemas/agent-adapters.schema.json`** | JSON Schema for the manifest |
| **`tools/verify-agent-adapters.ps1`** | Read-only validation (`-Json` for machine output) |

Policy background: **`policies/multi-tool-adapters.md`**.

---

## System state

| Component | Status |
|-----------|--------|
| Global CLAUDE.md | Stable |
| install.ps1 | Stable, dry-run validated |
| install.sh | Stable, dry-run + real-install validated (bash 5.2 / MSYS2 + Unix-compatible) |
| bootstrap-manifest.json | Source of truth for repo counts, skills, bootstrap scripts, and critical paths |
| tools/verify-os-health.ps1 | Primary health entrypoint — manifests, syntax, bootstrap, Bash, safe-output, git-hygiene, agent-adapters, dispatcher |
| source/skills/ | 6/6 — manifest verified and bootstrapped to `.claude/skills/` |
| policies/ | 8/8 — complete |
| prompts/ | 7/7 — complete |
| templates/commands/ | 18/18 — manifest verified |
| templates/scripts/ | 38/38 — manifest verified; health check runs `bash -n` |
| templates/invariant-engine/dist/ | 3/3 — invariant-engine, semantic-diff, simulate-contract-delta |
| templates/profiles/ | 2/2 — node-ts-service, react-vite-app |
| templates/agents/ | 5/5 — principal architect, QA strategist, release manager, reliability engineer, security engineer |
| templates/settings.json | Stable — 4 hooks + permissions |
| heuristics/ | operational.md + cross-project-evidence.json (MVP) |
| templates/critical-surfaces/ | 5/9 — auth, migrations, billing, deploy, pii |
| templates/adapters/ | 6/6 — AGENTS.md, Cursor rule, Codex .agent/ docs |
| templates/task-modes/ | 5/5 — bugfix, architecture, migration, incident-response, release-hardening |
| INDEX.md | Manifest-aligned navigation map |

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
| 11 | Skills layer | **Done** |
| 12 | Aggregate OS health check | **Done** |
