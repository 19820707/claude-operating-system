---
name: release-readiness
description: "Use when preparing a release candidate: strict validation, manifests, Git hygiene, adapter drift, and documented residual risk."
category: governance
version: 1.0.0
user-invocable: true
---

# Release Readiness

## Purpose

Prepare a release candidate using strict validation, manifest checks, clean Git state, adapter and skills drift checks, documentation consistency, and explicit residual risk.

## Non-goals

- Shipping without human approval on the release decision itself.

## Inputs

- Target branch or tag, change list, risk class, and validation profile (standard vs strict).

## Outputs

- Validation envelopes, drift reports, Git status summary, and a written residual-risk statement.

## Operating mode

- Default risk level: critical.
- Allowed modes: standard (preflight), strict (release gate).
- Human approval required for: Production, Critical, Incident, Migration, Release, Destructive (mandatory before merge or tag).
- Safe for autonomous execution: no for the final release decision; yes for running validators and collecting evidence.

## Procedure

1. Run profile `standard` then `strict` validators per `tools/os-validate.ps1` and `tools/os-validate-all.ps1`.
2. Confirm `verify-git-hygiene`, `verify-agent-adapter-drift`, and `verify-skills-drift` outcomes.
3. Run doc contract checks so README, `ARCHITECTURE.md`, manifests, and listed scripts align.
4. List open issues, skipped checks, and known defects explicitly as residual risk.
5. Obtain explicit human approval before tagging or production promotion.

## Validation

- No validator may be reported as passed if its envelope status is `warn`, `skip`, or `fail`.
- Release is blocked if strict skills or adapter drift checks fail.

## Failure modes

- Hidden debt: undocumented skips or “good enough” waivers without owners.
- Drift between canonical skills and generated adapter copies.

## Safety rules

- Do not expose secrets.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive production changes without approval and rollback.
- Do not overwrite undeclared user-local files.

## Examples

- See `examples/skills/release-readiness.md`.

## Related files

- `skills-manifest.json`, `policies/production-safety.md` (repo root)
