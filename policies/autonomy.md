# Autonomy policy (Claude OS)

## Purpose

Define how agents may operate **locally** with high autonomy while **never** becoming unsupervised production actors, **never** weakening validation gates, and **never** treating ambiguous validation states as success. Invariantes globais: `policies/invariants.md` (I-001–I-010).

## Non-goals

- Replacing CI/CD, human release authority, or production change control.
- Fully closed-loop (A4) execution on steward-class surfaces.
- Validator bypass, policy relaxation without approval, or false-green reporting.

## Autonomy levels (A0–A4)

| Level | Meaning |
|-------|---------|
| **A0** | Manual: human executes; OS is reference only. |
| **A1** | Assisted: agent proposes; human applies and validates. |
| **A2** | Semi-autonomous: bounded execution with human checkpoints. |
| **A3** | Autonomous **with gates**: default for reversible, non-critical engineering; mandatory human approval for risk transitions listed in `policies/autonomy-policy.json`. |
| **A4** | Fully autonomous closed loop: **forbidden** for critical surfaces; never the default. |

## Default posture

- Target **A3** for low/medium-risk, **reversible** work (diff + rollback path).
- Design-time goal ~95% autonomous **steps** on such work; **~5%** human time on steward approvals (not an enforced SLA).

## Allowed autonomous actions (machine contract)

Canonical list lives in **`policies/autonomy-policy.json`** → `allowedAutonomousActions`.  
Typical safe actions include: read, analyze, plan, dry-run, validate, format docs, update indexes, sync generated adapters (when governed), repair **reversible** drift, create examples/tests, schema-compatible manifest updates, generate evidence, re-run validation, summarize residual risk.

## Requires human approval (risk transitions)

Canonical list lives in **`policies/autonomy-policy.json`** → `requiresHumanApproval.surfaces`.  
Includes: production, release publish, destructive write, migration, incident action with external impact, security policy change, secret handling, validator bypass, policy relaxation, breaking schema change, removal of files, irreversible action.

## Professional rule

**The system may prepare everything. Humans approve the risk transition.**

## False green and validation honesty

- `warn`, `skip`, `unknown`, `degraded`, `blocked`, `not_run` are **not** success (align `runtime-budget.json` → `neverTreatAsPassed`).
- **Never** downgrade `fail` to `warn`.
- **Never** claim success if a required validation was skipped or did not return `ok` in the strict sense used by orchestrators (`os-validate`, `verify-os-health`).

## Evidence

- Prefer JSON envelopes and optional JSONL history (`tools/write-validation-history.ps1`).
- Autopilot reports must remain machine-auditable (see `docs/AUTONOMY.md` and `tools/os-autopilot.ps1`).

## Related

- `policies/invariants.md` — leis conservativas (I-001–I-010).
- `policies/auto-approve-matrix.md` — matriz L7 (nunca / autónomo se reversível+validado / sempre humano).
- `docs/AUTONOMY.md` — operator guide.
- `docs/APPROVALS.md` — human approval ledger.
- `schemas/autonomy-policy.schema.json` — JSON contract.
- `tools/verify-autonomy-policy.ps1` — policy verifier (`-Strict` for release-style rigor).
