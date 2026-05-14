---
name: upgrade-planner
description: "Use when bumping manifest schemaVersion or paired schemas and recording upgrade-manifest entries and docs/UPGRADE.md."
category: governance
version: 1.0.0
user-invocable: true
---

# Upgrade planner

## Purpose

Coordinate `upgrade-manifest.json`, `verify-upgrade-notes.ps1 -Strict`, and `docs/UPGRADE.md` so contract bumps include migration, rollback, validation command, and affected files.

## Non-goals

- Raising `schemaVersion` without a matching `contractBumps` row.

## Inputs

- Which JSON roots changed; new integer `schemaVersion`; migration text.

## Outputs

- New manifest `entries[]` row; human summary in UPGRADE.md; strict verify green.

## Operating mode

- Default risk level: medium.
- Allowed modes: planning/docs first; apply JSON edits in single atomic commit.
- Human approval required for: breaking consumers on shared forks (maintainer sign-off).
- Safe for autonomous execution: yes for drafting text; merge per policy.

## Procedure

1. Read watched list in `upgrade-manifest.json` (must match verifier canonical set).
2. Bump disk `schemaVersion`; append `entries` with `contractBumps` max ≥ new values.
3. `pwsh ./tools/verify-upgrade-notes.ps1 -Json -Strict`.

## Validation

- Strict release gate + json contracts pass.

## Failure modes

- Drift between `watchedContractFiles` and `verify-upgrade-notes.ps1` embedded list.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Bump `component-manifest.json` schemaVersion → one new entry documenting all touched contracts.

## Related files

- `upgrade-manifest.json`, `schemas/upgrade-manifest.schema.json`, `tools/verify-upgrade-notes.ps1`, `docs/UPGRADE.md`, `quality-gates/release.json`
