# Autonomy layer (Claude OS)

Claude OS targets **high autonomy** for reversible, local engineering work (~**A3** by default) while **preserving** human gates for steward-class risk transitions. This is **not** unsupervised production automation.

## Principles (non-negotiable)

- **No false green:** `warn`, `skip`, `unknown`, `degraded`, `blocked`, `not_run` are **not** success (see `runtime-budget.json` → `neverTreatAsPassed`, `docs/VALIDATION.md`).
- **No validator bypass** and **no policy relaxation** without human approval.
- **Never** downgrade `fail` to `warn` in reporting (see `tools/os-autopilot.ps1` and `policies/autonomy-policy.json` → `validationRules`).
- **Never** claim success if a required validation was skipped or did not return `ok` for the orchestrated path.

## Autonomy levels (A0–A4)

| Level | Summary |
|-------|---------|
| **A0** | Manual |
| **A1** | Assisted (propose / human applies) |
| **A2** | Semi-autonomous (bounded scope) |
| **A3** | **Default:** autonomous **with gates** — validate, dry-run, diff, evidence; human for risk transitions |
| **A4** | Fully closed autonomous — **forbidden** on critical surfaces |

Canonical definitions: `policies/autonomy.md`, `policies/autonomy-policy.json`.

## What can run autonomously

Machine list: `allowedAutonomousActions` in **`policies/autonomy-policy.json`** (snake_case tokens).  
Human phrasing **“repair non-destructive drift”** corresponds to the token **`repair_reversible_drift`** (avoids substring clashes with “destructive” in policy checks).  
Typical examples: read/analyze/plan, **dry-run**, **validate**, format docs, update indexes, sync **governed** generated adapters, that drift repair, examples/tests, schema-compatible manifest edits, **evidence**, re-validation, residual-risk summary.

Operational narrative (Portuguese): `docs/CAPACIDADES-OPERACIONAIS.md` §17.2–§17.3.

## What requires human approval

Surface IDs: `requiresHumanApproval.surfaces` in **`policies/autonomy-policy.json`** (production, release publish, destructive writes, migrations, incident actions with external impact, security policy changes, secret handling, validator bypass, policy relaxation, breaking schema changes, file removal, irreversible actions).

Rule: **The system may prepare everything. Humans approve the risk transition.** (`docs/APPROVALS.md`, §11 in `docs/CAPACIDADES-OPERACIONAIS.md`).

## Repair loop

`tools/os-autopilot.ps1` implements a bounded **re-validation** loop (`-MaxRepairAttempts`). It does **not** silently mutate the repo in v1: it re-runs validation to observe whether the tree is already clean after a hypothetical repair. File-changing repair must remain human- or `invoke-safe-apply`-governed.

## Evidence model

- Autopilot JSON output includes `validations`, `repairAttempts`, `evidence`, `residualRisk`, `requiresApproval`, `approvalReasons`.
- Optional JSONL: pass **`-WriteEvidence`** to append a line via `tools/write-validation-history.ps1` (see `docs/AUDIT-EVIDENCE.md`).

## Tools

| Script | Purpose |
|--------|---------|
| `tools/verify-autonomy-policy.ps1` | Validates `policies/autonomy-policy.json`; **`-Strict`** for release-style checks |
| `tools/os-autopilot.ps1` | Bounded orchestration: classify goal risk, run policy verifier + `os-validate`, optional evidence |

### Example (dry-run)

```powershell
pwsh ./tools/verify-autonomy-policy.ps1 -Json
pwsh ./tools/os-autopilot.ps1 -Goal "validate docs and repair non-destructive drift" -Profile quick -DryRun -Json
pwsh ./tools/os-validate.ps1 -Profile standard -Json
```

## Safe autonomous task examples

- Run `os-validate` quick/standard after doc-only edits.
- Refresh `docs-index.json` / `INDEX.md` with validators green.
- Regenerate examples under `examples/` and re-run `verify-examples.ps1`.

## Blocked task examples

- Publishing a Git tag / release artifact to production.
- Disabling a validator or editing `neverTreatAsPassed` to allow `warn` as pass.
- Applying migrations to production without ledger approval.

## Related

- `playbooks/autonomous-repair.md` — runbook skeleton.
- `source/skills/autonomous-runtime/SKILL.md` — agent-facing procedure.
- `schemas/autonomy-policy.schema.json` — JSON Schema for the policy file.
