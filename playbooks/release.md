# Playbook: Release

## Purpose

Prepare and ship a release candidate with strict validation, honest status reporting, and explicit residual risk.

## Trigger conditions

- A version tag or production promotion is planned, or release CI must go green before merge.

## Required inputs

- Change summary, target version or tag, risk class, and owner for sign-off.

## Risk level

**Critical** — can affect production users, data integrity, and rollback posture.

## Required approvals

- Human approval for **Release** and **Production** promotion before tagging or deploying.

## Approval ledger

Steward-class tags (**Release**, **Production**, **Critical**) require recording human sign-off in **`logs/approval-log.jsonl`** (append-only JSONL) per **`docs/APPROVALS.md`** and **`schemas/approval-log.schema.json`**. Append rows with **`pwsh ./tools/append-approval-log.ps1`**; validate structure with **`pwsh ./tools/verify-approval-log.ps1 -Json`**. Routine **`os-validate`** / health runs do **not** read this file.

## Preflight checks

- `pwsh ./tools/os-validate.ps1 -Profile standard -Json` (or stricter per policy).
- `pwsh ./tools/verify-git-hygiene.ps1 -Json` clean for release branches where policy requires it.
- Manifests and adapter/skills drift checks per `docs/SKILLS.md` and `agent-adapters-manifest.json`.

## Execution steps

1. Freeze scope; document open defects and waived checks.
2. Run standard then strict validation profiles as required by policy.
3. Collect validation JSON envelopes and attach or summarize in the release record.
4. Obtain explicit release sign-off from the accountable human.
5. Execute tag or deploy only after sign-off and successful gates.

## Validation steps

- No step reported **pass** unless exit code and JSON `status` are acceptable; **warn**, **skip**, **unknown**, **degraded**, and **blocked** are not treated as passed.
- Confirm drift validators and doc contract checks match the release surface.

## Rollback / abort criteria

- Abort if any blocking validator fails, secrets appear in logs, or sign-off is withdrawn.
- Rollback plan: revert tag, redeploy previous artifact, or restore config per runbook; document the chosen path before executing production changes.

## Evidence to collect

- Validation command outputs (redacted), Git revision, manifest versions, and sign-off reference (ticket or email id).

## Expected outputs

- Tagged artifact or merged release branch, release notes, and a short residual-risk statement.

## Failure reporting

- Report failed step name, exit code, first actionable line, and whether production was touched. Do not reclassify warnings as success.
