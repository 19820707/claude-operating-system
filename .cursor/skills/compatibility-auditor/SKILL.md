<!-- Generated from source/skills/compatibility-auditor/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/compatibility-auditor/SKILL.md. -->
---
name: compatibility-auditor
description: "Use when reconciling compatibility-manifest.json with script-manifest validator ids and platform matrix docs."
category: verification
version: 1.0.0
user-invocable: true
---

# Compatibility auditor

## Purpose

Keep `compatibility-manifest.json`, `docs/COMPATIBILITY.md`, and `verify-compatibility.ps1` aligned so every listed validator id exists and platform defaults are intentional.

## Non-goals

- Declaring support for hosts the team has not tested—use `best-effort` honestly.

## Inputs

- New tool id in `script-manifest.json`; optional per-validator `overrides`.

## Outputs

- Updated matrix rows; verify-compatibility JSON ok.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only verify; manifest edits in PR.
- Human approval required for: changing `supported` defaults on `gha-*` rows.
- Safe for autonomous execution: yes for verify.

## Procedure

1. `pwsh ./tools/verify-compatibility.ps1 -Json`.
2. Add validator row when adding `script-manifest` tool used in health/gates.
3. Document rationale in COMPATIBILITY.md table footnotes if needed.

## Validation

- `verify-compatibility` + `verify-components` strict pass.

## Failure modes

- Validator id typo; orphan platform id in overrides.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Add `verify-foo` to manifest → add `validators` entry + defaultSupport review.

## Related files

- `compatibility-manifest.json`, `docs/COMPATIBILITY.md`, `tools/verify-compatibility.ps1`, `script-manifest.json`
