<!-- Generated from source/skills/runtime-economy/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/runtime-economy/SKILL.md. -->
---
name: runtime-economy
description: "Use when choosing validation depth, cost, or execution order before expensive repo-wide work."
category: economy
version: 1.0.0
user-invocable: true
---

# Runtime Economy

## Purpose

Pick the cheapest sufficient validation or execution path before expensive operations. Prefer staged depth: quick, then standard, then strict.

## Non-goals

- Skipping safety gates for speed. Economy never overrides production-safety or incident constraints.

## Inputs

- Task hypothesis (what could be wrong), touched paths, and available validators or scripts.

## Outputs

- Ordered plan of checks, honest pass or fail or warn or skip labels, and explicit residual uncertainty.

## Operating mode

- Default risk level: medium.
- Allowed modes: quick, standard, strict (per repo validation profiles).
- Human approval required for: production mutation, destructive changes, release tagging.
- Safe for autonomous execution: yes, within read-only and manifest-scoped checks only.

## Procedure

1. Start with the narrowest hypothesis and smallest file set that can falsify it.
2. Order: quick before standard before strict; dry-run before write; diff before apply.
3. Avoid full-repo scans without a concrete hypothesis and a stop condition.
4. Treat `skip`, `warn`, `unknown`, `degraded`, and `blocked` as not-passed in reporting.
5. Escalate depth only when cheaper checks are inconclusive or risk warrants it.

## Validation

- Confirm each step’s exit code and JSON `status` where applicable; never coerce warn into pass.
- Re-run the next deeper profile only when the previous envelope is clean or explicitly documents why depth increased.

## Failure modes

- False green from treating warnings or skipped checks as success.
- Unbounded discovery or install steps before scoped checks complete.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- See `examples/skills/runtime-economy.md`.

## Related files

- `skills-manifest.json`, `policies/production-safety.md`, `policies/token-economy.md` (repo root)
