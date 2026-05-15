# Model Selection Policy (Global)

## Principle

Model assignment is a **risk and complexity decision**, not a performance preference.
Wrong model → insufficient reasoning depth → missed invariants → production incidents.

This policy is binding. Project-specific OPUS-MANDATORY surfaces are defined in each repo's `.claude/policies/model-selection.md`.

---

## Model Profiles

| Model | Strengths | Use | Cost |
|-------|-----------|-----|------|
| `claude-haiku-4-5-20251001` | Search, file reads, status checks, boilerplate | Discovery, grep, triagem, context prep | Low |
| `claude-sonnet-4-6` | Implementation, tests, CI config, observability, docs | Scoped implementation where design is already decided | Medium |
| `claude-opus-4-6` | Multi-constraint tradeoffs, security invariants, architectural boundary detection | Architecture, auth/authz, billing, publish gates, entitlement, migrations, incidents | High |

**Rule: Haiku discovers → Sonnet executes → Opus decides.**
Never escalate model without demonstrable technical need.

---

## Decision Matrix (by Operating Mode)

| Mode | Primary | Sub-agents | Override |
|------|---------|-----------|----------|
| **Fast** | Sonnet 4.6 | Haiku (search) | Escalate to Opus if critical surface touched |
| **Phase** | Opus 4.6 | Sonnet (execution) | No downgrade |
| **Critical** | Opus 4.6 | Sonnet (file edits) | Mandatory |
| **Production** | Opus 4.6 | Sonnet (docs) | Mandatory + human gate |

---

## Generic OPUS-MANDATORY Surfaces

Any task touching:
- auth / authz / entitlement logic
- billing / payment flows
- publish gates
- non-additive schema migrations
- incident root cause analysis
- irreversible architectural decisions
- cross-module security invariants

---

## Agent → Model

| Agent | Model |
|-------|-------|
| principal-architect | Opus |
| security-engineer | Opus |
| release-manager | Opus |
| qa-strategist | Sonnet |
| reliability-engineer | Sonnet |
| Explore sub-agents | Haiku |
| Plan sub-agents | Opus |

---

## Escalation Rules

1. Fast-mode Sonnet touches OPUS-MANDATORY surface → stop, escalate
2. Haiku sub-agent finds security anomaly → surface to Opus immediately
3. No mid-task model downgrade for speed
4. Uncertainty about model tier → default to Opus (fail-safe)
5. Validation failure on critical path → Opus diagnoses, Sonnet executes fix only

---

## Handoff: Opus → Sonnet

1. Opus outputs explicit spec: target files, invariants, acceptance criteria, what NOT to touch
2. Sonnet executes edits only
3. Sonnet validates: typecheck + target tests
4. Failure → return to Opus for diagnosis

---

## Project-Specific Overrides

Each project defines its own OPUS-MANDATORY file paths in:
`.claude/policies/model-selection.md`

That file extends this global policy with project-specific surfaces.
