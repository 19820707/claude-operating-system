---
name: incident-safe-change
description: "Use when responding to incidents or production-sensitive work where minimal scope, evidence, rollback, approval, and post-change validation are required."
category: safety
version: 1.0.0
user-invocable: true
---

# Incident Safe Change

## Purpose

Guide changes during incidents or production-sensitive operations: minimal blast radius, explicit rollback, human approval for risky steps, evidence before action, post-change validation, and clear residual risk.

## Non-goals

- Large refactors or feature work mixed with incident response.

## Inputs

- Incident state, severity, affected systems, current metrics or logs (summarized), and change proposal.

## Outputs

- Minimal diff or runbook steps, rollback checkpoints, validation results, and residual risk notes.

## Operating mode

- Default risk level: critical.
- Allowed modes: mitigation and stabilization only until service health is restored.
- Human approval required for: Production, Critical, Incident, Migration, Release, Destructive (non-negotiable for production mutation).
- Safe for autonomous execution: no for production writes; yes for read-only triage and validation.

## Procedure

1. Freeze scope: one hypothesis and one primary change vector at a time.
2. Document rollback before executing irreversible steps.
3. Gather minimal sufficient evidence; avoid dumping sensitive raw logs into chat.
4. Execute smallest change; validate with targeted checks, not full unrelated suites unless warranted.
5. Record outcomes, residual risk, and follow-up owners.

## Validation

- Post-change checks explicitly tied to the touched surface; status honestly reported.

## Failure modes

- Multiple concurrent uncoordinated changes without rollback clarity.
- Skipping validation because “it should be fine.”

## Safety rules

- Do not expose secrets.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without explicit human approval.
- Do not overwrite user-local files except via safe, declared generation paths.

## Examples

- See `examples/skills/incident-safe-change.md`.

## Related files

- `skills-manifest.json`, `policies/production-safety.md` (repo root)
