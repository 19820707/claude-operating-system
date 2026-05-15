<!-- Generated from source/skills/approval-ledger/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/approval-ledger/SKILL.md. -->
---
name: approval-ledger
description: "Use when executing steward-class playbooks and recording human sign-off in logs/approval-log.jsonl per docs/APPROVALS.md."
category: safety
version: 1.0.0
user-invocable: true
---

# Approval ledger

## Purpose

Apply `docs/APPROVALS.md`, `schemas/approval-log.schema.json`, `append-approval-log.ps1`, and `verify-approval-log.ps1` for **Release / Production / Critical / Incident / Migration / Destructive** playbook work—not for routine `os-validate`.

## Non-goals

- Fabricating approvals or reusing one-time tokens after execution.

## Inputs

- Operation name; scope; command approved; evidence lines; rollback pointer; `-ExpiresAt` or `-OneTimeUse`.

## Outputs

- One JSONL line; optional `-Json` envelope from append tool.

## Operating mode

- Default risk level: high.
- Allowed modes: append after human sign-off; `-WhatIf` rehearsal.
- Human approval required for: **Release**, **Production**, **Critical**, **Incident**, **Migration**, **Destructive** real execution.
- Safe for autonomous execution: no for append; yes for verify-approval-log read.

## Procedure

1. Follow steward playbook `## Approval ledger` section + `playbooks/README.md`.
2. `pwsh ./tools/append-approval-log.ps1` with real `-Approver` after placeholder phase.
3. `pwsh ./tools/verify-approval-log.ps1 -Json` to validate JSONL shape if file exists.

## Validation

- JSON line parses; `expirationOrUse` rule satisfied; evidence non-empty array.

## Failure modes

- Missing ledger section on steward-tagged playbook (CI fail). Malformed JSONL breaks verify.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Before prod migration cutover: append row with `oneTimeUse` and rollback anchor to `playbooks/migration.md`.

## Related files

- `docs/APPROVALS.md`, `schemas/approval-log.schema.json`, `tools/append-approval-log.ps1`, `tools/verify-approval-log.ps1`, `playbooks/release.md`, `playbooks/incident.md`, `playbooks/migration.md`
