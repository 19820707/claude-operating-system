---
name: deprecation-manager
description: "Use when adding deprecations, checking strict surfaces, or running verify-deprecations before release."
category: governance
version: 1.0.0
user-invocable: true
---

# Deprecation manager

## Purpose

Maintain `deprecation-manifest.json`, dates, replacements, and `verify-deprecations.ps1 -Strict` alignment with `os-validate`, quality gates, and orchestrator scans.

## Non-goals

- Deleting deprecated tools without migration window and manifest update.

## Inputs

- Deprecation id; target paths; allowedInStrictMode flags.

## Outputs

- Updated manifest; CI green on strict deprecations gate.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only verify; manifest edits with PR.
- Human approval required for: `allowedInStrictMode: false` items still referenced on release surfaces.
- Safe for autonomous execution: yes for verify; edits need review.

## Procedure

1. `pwsh ./tools/verify-deprecations.ps1 -Json -Strict`.
2. Add entry with ISO dates and replacement; grep orchestrators for target strings.
3. Remove from strict surfaces before flipping flags.

## Validation

- Strict deprecations + release gate pass.

## Failure modes

- Deprecated script still listed in `quality-gates/release.json` without allow path.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Mark tool deprecated → remove from `os-validate.ps1` string refs or gate lists in same change.

## Related files

- `deprecation-manifest.json`, `tools/verify-deprecations.ps1`, `quality-gates/`, `tools/os-validate.ps1`
