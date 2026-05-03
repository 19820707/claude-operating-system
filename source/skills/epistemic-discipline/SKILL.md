---
name: epistemic-discipline
description: "Use when decisions depend on assumptions, inferred facts, unknowns, disputed evidence, or confidence-sensitive execution."
category: verification
version: 1.0.0
user-invocable: true
---

# Epistemic Discipline

Use this skill when the task requires separating what is known from what is inferred, assumed, unknown, or disputed.

## Operating contract

- Classify important claims as KNOWN, INFERRED, ASSUMED, DISPUTED, or UNKNOWN.
- **Structural confidence (graphify ↔ OS):** see **`ARCHITECTURE.md`** section *Session pipeline (graphify-aligned stance)* for `EXTRACTED`/`INFERRED`/`AMBIGUOUS` mapping and session-table indexing.
- Do not act on assumptions as if they were facts.
- Promote assumptions to known facts only with evidence.
- Block high-risk action when required unknowns remain unresolved.
- Keep confidence notes short and tied to decisions.

## Required checks

1. Identify decision-critical facts.
2. Mark unresolved assumptions and unknowns.
3. Run `bash .claude/scripts/epistemic-check.sh --gate` when the decision has risk.
4. Record decision debt when action proceeds with known uncertainty.
5. Revisit disputed facts before final approval.

## Invariants

- Unknowns that affect safety, money, data, auth, or production block autonomous execution.
- Assumptions must be labeled, not hidden in prose.
- Evidence outranks confidence language.
- Decision debt must be visible after handoff.
