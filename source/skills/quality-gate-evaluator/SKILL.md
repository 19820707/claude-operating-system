---
name: quality-gate-evaluator
description: "Use when interpreting or authoring quality-gates/*.json and running evaluate-quality-gate for a domain gate."
category: verification
version: 1.0.0
user-invocable: true
---

# Quality gate evaluator

## Purpose

Apply `schemas/quality-gate.schema.json`, `verify-quality-gates.ps1`, and `evaluate-quality-gate.ps1` so required validators, evidence strings, and false-green rules stay coherent.

## Non-goals

- Owning human approval workflows outside the JSON contracts.

## Inputs

- Gate file path; repo root; strict release policy when evaluating `gate.release`.

## Outputs

- Gate JSON result; list of validator script/arg mismatches or evidence gaps.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only evaluation; editing gate JSON is controlled change.
- Human approval required for: editing `quality-gates/release.json` on protected branches.
- Safe for autonomous execution: yes for evaluate; no for unreviewed gate edits in prod repos.

## Procedure

1. Structural: `pwsh ./tools/verify-quality-gates.ps1 -Json`.
2. Single gate: `pwsh ./tools/evaluate-quality-gate.ps1` with correct parameters (see tool header).
3. Align `requiredEvidence` with `tests/contracts/release-evidence-keywords.json` when touching release.

## Validation

- Gate passes only with `status` ok per `neverTreatAsPassed` semantics in docs.

## Failure modes

- Validator id in JSON not present in `script-manifest.json`. Evidence line with no keyword mapping.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- After adding `verify-foo.ps1`: register in manifest, gate JSON, then contract-tests.

## Related files

- `quality-gates/`, `schemas/quality-gate.schema.json`, `tools/verify-quality-gates.ps1`, `tools/evaluate-quality-gate.ps1`, `docs/QUALITY-GATES.md`
