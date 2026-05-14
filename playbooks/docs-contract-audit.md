# Playbook: Documentation contract audit

## Purpose

Ensure README, INDEX, manifests, schemas, and referenced tools stay aligned and avoid false-green wording.

## Trigger conditions

- Docs or manifest churn, new validators, or release prep requiring contract hygiene.

## Required inputs

- List of files touched in the PR and any renamed scripts or entrypoints.

## Risk level

**Medium** — incorrect docs mislead operators and agents.

## Required approvals

- Optional for read-only audit; human review before merging doc claims about CI or safety behavior.

## Preflight checks

- `pwsh ./tools/verify-doc-contract-consistency.ps1 -Json`
- `pwsh ./tools/verify-doc-manifest.ps1`

## Execution steps

1. Run doc contract and doc manifest verifiers.
2. Manually spot-check README command examples against `tools/*.ps1` and `script-manifest.json`.
3. Fix mismatches in docs or manifests; prefer manifests as source of truth for counts.

## Validation steps

- Re-run verifiers until clean; grep for unsafe phrases like equating **skip** or **warn** to **passed** in user-facing docs.

## Rollback / abort criteria

- Abort merge if verifiers still fail; revert doc-only commits if they introduced false claims.

## Evidence to collect

- Verifier JSON status lines or short logs attached to the PR.

## Expected outputs

- Updated docs and green doc verifiers on the target branch.

## Failure reporting

- List each broken reference or unsafe phrase with file path and suggested fix.
