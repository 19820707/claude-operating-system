---
name: lifecycle-manager
description: "Use when editing lifecycle-manifest install/init/update commands or verifying paths with verify-lifecycle."
category: governance
version: 1.0.0
user-invocable: true
---

# Lifecycle manager

## Purpose

Govern `lifecycle-manifest.json` phases, `scriptPath` existence, field lengths, and `verify-lifecycle.ps1` so install/init/update stories stay executable.

## Non-goals

- Changing production runbooks without `playbooks/migration.md` alignment.

## Inputs

- Phase id; entrypoint script; validationAfterExecution text.

## Outputs

- Manifest diff; verify-lifecycle pass envelope.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only verify; JSON edits with review.
- Human approval required for: shortening validation strings below minimums (schema fail).
- Safe for autonomous execution: yes for verify.

## Procedure

1. `pwsh ./tools/verify-lifecycle.ps1 -Json`.
2. Ensure each command’s `scriptPath` exists when set; keep rollbackBehavior honest.
3. Cross-link to `docs/LIFECYCLE.md` for human narrative.

## Validation

- Health lifecycle step + json contracts include lifecycle pair.

## Failure modes

- Broken relative scriptPath; duplicate command ids.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Add update-phase hook → new row + `tools/` script + verify-lifecycle green.

## Related files

- `lifecycle-manifest.json`, `schemas/lifecycle-manifest.schema.json`, `tools/verify-lifecycle.ps1`, `docs/LIFECYCLE.md`
