# Model Selection Policy (Global)

## Principle

Model assignment is a **risk and complexity decision**, not a performance preference. Delegation is also a cost decision.
Wrong model → insufficient reasoning depth → missed invariants → production incidents. Wrong delegation → wasted context, duplicated reads, and slower execution.

This policy is binding. Project-specific OPUS-MANDATORY surfaces are defined in each repo's `.claude/policies/model-selection.md`.

---

## Model Profiles

| Model | Strengths | Use | Cost |
|-------|-----------|-----|------|
| `claude-haiku-4-5-20251001` | Search, file reads, status checks, boilerplate | Bounded discovery only when discovery is allowed | Low |
| `claude-sonnet-4-6` | Implementation, tests, CI config, observability, docs | Scoped implementation where design is already decided | Medium |
| `claude-opus-4-6` | Multi-constraint tradeoffs, security invariants, architectural boundary detection | Architecture, auth/authz, billing, publish gates, entitlement, migrations, incidents | High |

**Rule: Haiku discovers → Sonnet executes → Opus decides** applies only after the task has been scoped and delegation is justified.
Never escalate model or delegate work without demonstrable technical need.

---

## Decision Matrix (by Operating Mode)

| Mode | Primary | Sub-agents | Override |
|------|---------|-----------|----------|
| **Fast** | Sonnet 4.6 | None by default; Haiku only for justified bounded search | Escalate to Opus if critical surface touched |
| **Phase** | Opus 4.6 | Sonnet for execution after explicit spec | No downgrade |
| **Critical** | Opus 4.6 | Sonnet for file edits only after Opus plan | Mandatory |
| **Production** | Opus 4.6 | Sonnet for docs or mechanical edits only | Mandatory + human gate |

---

## Delegation gates

Do **not** dispatch `Explore` / sub-agents when the task has:

- a named file or short file list;
- a concrete diff, commit, or failing test;
- a known component or narrow route;
- an instruction to operate in token-economy / surgical mode;
- a prior discovery result in the same phase.

For those tasks, the main session reads target paths first and expands by one dependency ring only when evidence requires it.

Sub-agents are allowed only when:

- the user explicitly requests repo-wide audit, architecture review, security review, migration plan, release review, or incident triage;
- the target subsystem is unknown after a surgical first pass;
- independent subsystems must be inspected in parallel and the stop condition is explicit;
- the work is Opus-mandatory and needs separate execution after Opus defines scope.

Every sub-agent dispatch must include:

1. reason;
2. maximum files/directories;
3. stop condition;
4. expected artifact;
5. token/output budget.

Open-ended exploration is not allowed.

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

| Agent | Model | Constraint |
|-------|-------|------------|
| principal-architect | Opus | Broad architecture only; requires scoped objective |
| security-engineer | Opus | Security/auth/secrets surfaces only |
| release-manager | Opus | Release/go-no-go only |
| qa-strategist | Sonnet | Test strategy; no repo crawl unless requested |
| reliability-engineer | Sonnet | Reliability/failure-mode work; scoped subsystem first |
| Explore sub-agents | Haiku | Only after delegation gates pass |
| Plan sub-agents | Opus | Only for critical/architecture decisions |

---

## Escalation Rules

1. Fast-mode Sonnet touches OPUS-MANDATORY surface → stop, escalate.
2. Haiku sub-agent finds security anomaly → surface to Opus immediately.
3. No mid-task model downgrade for speed.
4. Uncertainty about model tier on critical surfaces → default to Opus (fail-safe).
5. Uncertainty about scope on non-critical tasks → stay surgical and ask for the smallest expansion.
6. Validation failure on critical path → Opus diagnoses, Sonnet executes fix only.

---

## Handoff: Opus → Sonnet

1. Opus outputs explicit spec: target files, invariants, acceptance criteria, what NOT to touch.
2. Sonnet executes edits only.
3. Sonnet validates: typecheck + target tests.
4. Failure → return to Opus for diagnosis.

---

## Project-Specific Overrides

Each project defines its own OPUS-MANDATORY file paths in:
`.claude/policies/model-selection.md`

That file extends this global policy with project-specific surfaces.
