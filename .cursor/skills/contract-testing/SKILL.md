<!-- Generated from source/skills/contract-testing/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/contract-testing/SKILL.md. -->
---
name: contract-testing
description: "Use when validating cross-manifest contracts, doc commands, and release evidence mapping before merge."
category: verification
version: 1.0.0
user-invocable: true
---

# Contract testing

## Purpose

Drive `run-contract-tests.ps1`, `verify-json-contracts.ps1`, and aligned pairs; keep manifest/schema pairs and `tests/contracts/release-evidence-keywords.json` in sync with `quality-gates/release.json`.

## Non-goals

- Replacing full `os-validate-all -Strict` or project application tests.

## Inputs

- Repo root; awareness of which manifest pair changed.

## Outputs

- Contract test JSON envelope; concrete file pairs to fix when drift fails.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only.
- Human approval required for: none for running tests; for changing release gate contracts, use release playbook.
- Safe for autonomous execution: yes.

## Procedure

1. After manifest edits: `pwsh ./tools/verify-json-contracts.ps1`.
2. `pwsh ./tools/run-contract-tests.ps1 -Json`; fix failures before widening scope.
3. If `requiredEvidence` text changes, update `tests/contracts/release-evidence-keywords.json`.

## Validation

- Both tools exit 0; release gate evaluator still passes if applicable.

## Failure modes

- Adding gate evidence lines without keyword mapping. Silent skip of new manifests in `run-contract-tests` pairs.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Bump `upgrade-manifest.json` → run contracts + upgrade-notes strict.

## Related files

- `tools/run-contract-tests.ps1`, `tools/verify-json-contracts.ps1`, `tests/contracts/README.md`, `quality-gates/release.json`
