# Playbook: Data or platform migration

## Purpose

Move data or platform dependencies with rehearsal, checkpoints, and verifiable cutover.

## Trigger conditions

- Schema change, datastore cutover, cluster move, or dependency upgrade that touches production data paths.

## Required inputs

- Migration plan document, source and target topology, downtime window, and DBA or owner sign-off where required.

## Risk level

**High** — data loss or extended outage if mis-executed.

## Required approvals

- Human approval for **Migration**, **Production**, and **Destructive** steps before irreversible transforms.

## Approval ledger

Steward-class tags (**Migration**, **Production**, **Destructive**) require recording human sign-off in **`logs/approval-log.jsonl`** (append-only JSONL) per **`docs/APPROVALS.md`** and **`schemas/approval-log.schema.json`**. Append rows with **`pwsh ./tools/append-approval-log.ps1`**; validate structure with **`pwsh ./tools/verify-approval-log.ps1 -Json`**. Routine **`os-validate`** / health runs do **not** read this file.

## Preflight checks

- Backup or snapshot verified restorable.
- Dry-run or shadow traffic completed for the same code path as production.
- Row counts or checksum contracts defined for post-migration validation.

## Execution steps

1. Enable maintenance or read-only mode if in scope.
2. Apply schema or data steps in documented order with checkpoints.
3. Run cutover script or traffic switch only after preflight sign-off.
4. Execute validation queries before declaring complete.
5. Remove maintenance mode and monitor error budgets.

## Validation steps

- Compare checksums, counts, or sampled rows against baseline; fail closed on mismatch.
- Application health checks and canary metrics must be green before closing the window.

## Rollback / abort criteria

- Abort cutover if validation fails mid-flight; restore from snapshot per plan.
- If partial apply occurred, follow the documented partial-state procedure before retry.

## Evidence to collect

- Before/after metrics, migration job ids, validation query results, and approver references.

## Expected outputs

- Migrated system in steady state, monitoring dashboards stable, and migration record archived.

## Failure reporting

- File incident if customer impact; include exact step failed and whether rollback ran.
