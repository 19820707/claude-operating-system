# Playbook: Incident response

## Purpose

Stabilize service during an incident with minimal blast radius, clear approvals, and auditable evidence.

## Trigger conditions

- Customer-facing outage, SLO burn, security event, or on-call page requiring immediate mitigation.

## Required inputs

- Incident commander, severity, affected systems, current error rates or logs (summarized), and communication channel.

## Risk level

**Critical** — production changes under uncertainty.

## Approval ledger

Steward-class tags (**Incident**, **Production**, **Critical**) require recording human sign-off in **`logs/approval-log.jsonl`** (append-only JSONL) per **`docs/APPROVALS.md`** and **`schemas/approval-log.schema.json`**. Append rows with **`pwsh ./tools/append-approval-log.ps1`**; validate structure with **`pwsh ./tools/verify-approval-log.ps1 -Json`**. Routine **`os-validate`** / health runs do **not** read this file.

## Required approvals

- Human approval for **Incident** and **Production** mutations beyond read-only diagnostics.

## Preflight checks

- Confirm rollback lever exists (feature flag, config revert, or previous deploy).
- Ensure on-call and stakeholders are identified before irreversible steps.

## Execution steps

1. Triage: scope hypothesis, stop bleeding (rate limit, circuit break, scale, or rollback).
2. Communicate status and ETA without speculating beyond evidence.
3. Apply the smallest change with a named owner; avoid parallel uncoordinated edits.
4. Run targeted validation after each change.
5. Hand off to postmortem owner with timeline and evidence pointers.

## Validation steps

- Metrics or health checks move toward baseline; if not, stop and widen rollback consideration.
- Never treat **warn** or **skip** as resolved without explicit owner acceptance.

## Rollback / abort criteria

- Abort if blast radius grows without approval or if validation contradicts the hypothesis.
- Rollback to last known-good deploy or disable the change via the pre-agreed lever.

## Evidence to collect

- Timestamps, dashboards (screenshots or links), config diffs, command outputs (redacted), and decision log entries.

## Expected outputs

- Service stability restored or clearly bounded workaround, incident timeline, and follow-up tasks.

## Failure reporting

- State what was tried, what failed validation, and current customer impact; escalate if stuck beyond SLA.
