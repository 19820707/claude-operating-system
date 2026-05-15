# Playbook: Adapter drift repair

## Purpose

Restore parity between canonical sources and generated Claude/Cursor (and related) adapter copies using sync tools, not hand edits.

## Trigger conditions

- `verify-agent-adapter-drift.ps1` or `verify-skills-drift.ps1` reports drift or missing generated files before release.

## Required inputs

- `agent-adapters-manifest.json`, `skills-manifest.json`, and repo root with sync scripts available.

## Risk level

**High** — wrong writes can clobber adapter trees or bypass review.

## Required approvals

- Human approval for **Release**, **Migration**, or **Destructive** sync when it touches protected branches or production mirrors.

## Approval ledger

Steward-class tags (**Release**, **Migration**, **Destructive**) require recording human sign-off in **`logs/approval-log.jsonl`** (append-only JSONL) per **`docs/APPROVALS.md`** and **`schemas/approval-log.schema.json`**. Append rows with **`pwsh ./tools/append-approval-log.ps1`**; validate structure with **`pwsh ./tools/verify-approval-log.ps1 -Json`**. Routine **`os-validate`** / health runs do **not** read this file.

## Preflight checks

- Review diff: canonical vs generated; confirm canonical should win.
- Ensure no local-only edits in generated paths you intend to keep.

## Execution steps

1. Run `pwsh ./tools/sync-skills.ps1 -DryRun -Json`, then apply if plan is correct.
2. Run `pwsh ./tools/sync-agent-adapters.ps1` per manifest (with dry-run if supported).
3. Re-run drift validators; use `-Strict` in release gates.

## Validation steps

- Drift tools report match or acceptable absence per policy; CI must not downgrade warnings to passed.

## Rollback / abort criteria

- Abort if sync targets paths outside manifest `generatedTargets` or adapter map.
- Roll back Git changes to generated trees if sync was mistaken; restore from branch tip.

## Evidence to collect

- Drift JSON findings before and after, list of paths written, and reviewer id.

## Expected outputs

- Clean drift checks and committed regenerated files where policy requires them in git.

## Failure reporting

- Report which target drifted and whether canonical or generated was chosen as truth; never hide partial sync.
