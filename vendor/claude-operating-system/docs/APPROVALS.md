# Human approval ledger

Claude OS separates **routine local validation** (profiles, health, drift) from **steward-class execution** where a human must explicitly approve scope before irreversible or production-impacting steps run.

## Steward classes (ledger-backed)

These **playbook-manifest** `requiresApprovalFor` tags require an **Approval ledger** section in the playbook Markdown and use of this ledger when executing that playbook for real:

| Tag | Typical use |
|-----|----------------|
| **Release** | Tags, merges, release CI promotion |
| **Production** | Live traffic, prod config, customer data paths |
| **Critical** | Integrity, auth, billing, or safety-critical surfaces |
| **Incident** | Break-glass, incident commands, production stabilization |
| **Migration** | Data move, cutover, schema changes |
| **Destructive** | Deletes, overwrites, non-idempotent infra |

Playbooks that declare **none** of the above (for example **bootstrap-project** or **docs-contract-audit**) do **not** require ledger wiring for manifest compliance.

**Normal local validation** — `pwsh ./tools/os-validate.ps1` (any profile), `pwsh ./tools/verify-os-health.ps1`, recipe checks, and similar — **does not** read or require rows in `logs/approval-log.jsonl`.

## Before requesting approval (pre-flight)

Before a human signs off or before you append a ledger row, make the following explicit in the playbook body, ticket, or session summary (Portuguese operational framing: [`docs/CAPACIDADES-OPERACIONAIS.md`](CAPACIDADES-OPERACIONAIS.md) §11):

| Topic | Ledger / repo mapping |
|-------|------------------------|
| **Scope** | `-Scope` → `scope` |
| **Risk** | `-RiskLevel` → `riskLevel`; prose may extend `-Operation` |
| **Execution plan** | `-CommandOrActionApproved` → `commandOrActionApproved` |
| **Rollback plan** | `-RollbackPlanReference` → `rollbackPlanReference` |
| **Prior validation & evidence** | `-RelatedValidationEvidence` → `relatedValidationEvidence` (≥1 pointer: JSON envelope path, CI URL, commit SHA, redacted transcript) |
| **Expected impact, known issues, residual risk** | Not separate schema fields—capture in playbook text, ticket, or summarize inside `scope` / `operation` as needed |

## Ledger file

- **Path:** `logs/approval-log.jsonl` (directory is gitignored; ledger stays local or is copied to your evidence store).
- **Format:** one JSON object per line, UTF-8, no trailing commas. Shape is defined by **`schemas/approval-log.schema.json`**.

## Append a row

From repo root, pass all required fields. You must supply **either** `-ExpiresAt` (RFC 3339 UTC) **or** `-OneTimeUse` (or both).

```powershell
pwsh ./tools/append-approval-log.ps1 `
  -Operation 'Release tag v1.2.0' `
  -RiskLevel critical `
  -Approver 'pending:release-owner' `
  -Scope 'claude-operating-system main; prod deploy window' `
  -CommandOrActionApproved 'git tag v1.2.0 && git push origin v1.2.0' `
  -OneTimeUse `
  -RelatedValidationEvidence @('pwsh ./tools/os-validate-all.ps1 -Strict -Json exit 0','commit abcdef1') `
  -RollbackPlanReference 'playbooks/release.md##rollback--abort-criteria' `
  -Json
```

After replacing placeholders, re-run with the real **`-Approver`** identity. Use **`-Json`** to emit a compact validator envelope on success. Rehearse with **`-WhatIf`** (no line is written; the script still validates parameters).

## Verify structure

- **`pwsh ./tools/verify-approval-log.ps1 -Json`** — Ensures steward playbooks document the ledger; if `logs/approval-log.jsonl` exists, validates each line against the schema contract (structural checks in PowerShell).

## Approver placeholder

Until sign-off is complete, use a clear placeholder in **`-Approver`**, for example `pending:<role>` or `pending:<ticket-id>`. Replace it in a follow-up append or in your external ticketing system; the ledger line itself is immutable once written (append-only).

## Rollback plan reference

Point to a stable anchor: playbook section, `docs/` path, ticket, or change id. The field is evidence for auditors, not an executable command.
