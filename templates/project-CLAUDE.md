# CLAUDE.md — [PROJECT NAME]

Global engineering policies apply from `~/.claude/CLAUDE.md`.
This file contains only project-specific context.

---

## Session Continuity — READ FIRST

At the start of every session:
1. Read `~/.claude/CLAUDE.md` (global policies + learning system)
2. Read `.claude/session-state.md` (branch, decisions, risks, next steps)
3. Read `.claude/learning-log.md` (phase patterns, heuristics, anti-patterns)
4. Do not assume state from chat history

At the end of every session: update `.claude/session-state.md`.
At the end of every phase: append to `.claude/learning-log.md` via `/phase-close`.

---

## Project Context

**Stack:** <!-- e.g. Node.js / TypeScript / React / PostgreSQL -->
**Branch model:** <!-- e.g. main (production) / develop (active) -->
**Platform:** <!-- e.g. Vercel / AWS / Hostinger -->

---

## Repo-Specific Policies

| Policy | File |
|--------|------|
| Operating modes | `.claude/policies/operating-modes.md` |
| Model selection (with project surfaces) | `.claude/policies/model-selection.md` |
| Engineering governance | `.claude/policies/engineering-governance.md` |
| Production safety | `.claude/policies/production-safety.md` |

---

## Critical Surfaces (Opus mandatory)

<!-- List the specific files/modules in this project that require Opus -->
<!-- Example: -->
<!-- - `src/auth/engine.ts` -->
<!-- - `src/billing/gateway.ts` -->

---

## Living architecture graph (optional)

Structural import graph (computed): run `bash .claude/scripts/living-arch-graph.sh` — output `.claude/architecture-graph.json`. Blast radius before edits: `bash .claude/scripts/living-arch-graph.sh --blast-radius <path>`. Layer rules: `.claude/architecture-boundaries.json`.

**Invariant engine (AST):** `bash .claude/scripts/invariant-verify.sh` — specs `.claude/invariants/*.json`, report `.claude/invariant-report.json`.

**Invariant lifecycle (temporal):** `bash .claude/scripts/invariant-lifecycle.sh` — registry `.claude/invariants.json`, report `invariant-lifecycle-report.json` (staleness / obsolescence / genealogy); opcional `--for <path>` e `--apply`.

**Multi-agent coordination:** `bash .claude/scripts/coordination-check.sh` — `.claude/agent-state.json` (leases, intentions, shared decisions) vs paths; `--paths` ou `COORDINATION_PATHS` / `COORDINATION_WT`; relatório `coordination-report.json`. Pré-flight: `COORDINATION_CHECK=1`, `COORDINATION_SESSION`, `COORDINATION_WT=0` se só quiseres paths explícitos.

**Epistemic state:** `bash .claude/scripts/epistemic-check.sh` — `.claude/epistemic-state.json`; `--summary`, `--gate --depends`, `--score-decision`, `--decision-debt`; `epistemic-report.json`. Pré-flight: `EPISTEMIC_CHECK=1`, `EPISTEMIC_PLAN_DEPENDS`. No decision log: campo opcional `epistemic_fact_keys` (ver `decision-log.schema.json`).

**Probabilistic risk:** `bash .claude/scripts/probabilistic-risk-model.sh --file <path>` → `.claude/risk-model.json`.

**Semantic diff:** `bash .claude/scripts/semantic-diff-analyze.sh --file <path.ts>` → `.claude/semantic-diff-report.json`.

**Learning loop:** `bash .claude/scripts/autonomous-learning-loop.sh` → `.claude/learning-loop-report.json` (anomalias / hipóteses; promoção manual).

**Decision audit:** append-only `.claude/decision-log.jsonl` via `decision-append.sh`; auditor `policy-compliance-audit.sh` → `policy-audit-report.json`.

**Context topology:** `context-topology.sh` → `.claude/knowledge-graph.json`; `--inject` / `--budget`.

---

## Active Roadmap

<!-- Current phase and epic sequence -->
<!-- See `.claude/session-state.md` for detail -->

---

## Agents

<!-- List agents available in .claude/agents/ -->

---

## Engineering OS — Auto-injected context

@.claude/session-state.md
@.agents/OPERATING_CONTRACT.md
@.claude/heuristics/operational.md
