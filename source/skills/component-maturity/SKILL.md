---
name: component-maturity
description: "Use when mapping tools and manifests into component-manifest tiers or running verify-components strict for release surfaces."
category: verification
version: 1.0.0
user-invocable: true
---

# Component maturity

## Purpose

Maintain `component-manifest.json`: core vs stable vs experimental members, `strictReleaseExperimentalAllowlist`, and `verify-components.ps1 -Strict` so release gates never resolve forbidden experimental tools.

## Non-goals

- Silently widening allowlists to greenwash strict failures.

## Inputs

- New tool id or manifest path; target component id; maturity enum.

## Outputs

- Updated `members` arrays; verify-components envelope ok.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only verify; JSON edits via PR.
- Human approval required for: allowlist additions touching **Release** surface.
- Safe for autonomous execution: yes for verify.

## Procedure

1. `pwsh ./tools/verify-components.ps1 -Json -Strict`.
2. Place new validator tool under `stable-delivery` unless truly core.
3. Link gate validators under `gateValidator` entries to match `quality-gates/*.json`.

## Validation

- Strict components + release readiness docs consistent.

## Failure modes

- Universe item (manifest path or tool) not mapped to any component. Experimental tool on release path.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Add `verify-foo`: register in `script-manifest`, `component-manifest` stable-delivery, `compatibility-manifest`, then strict verify.

## Related files

- `component-manifest.json`, `schemas/component-manifest.schema.json`, `tools/verify-components.ps1`, `docs/COMPONENTS.md`, `quality-gates/release.json`
