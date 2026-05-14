# Autonomy layer (Claude OS)

Claude OS targets **high autonomy** for reversible, local engineering work (~**A3** by default) while **preserving** human gates for steward-class risk transitions. This is **not** unsupervised production automation.

## Principles (non-negotiable)

- **No false green:** `warn`, `skip` / `skipped`, `unknown`, `degraded`, `blocked`, `not_run` are **not** success (see `runtime-budget.json` → `neverTreatAsPassed`, `gate-status-contract.json`, `pwsh ./tools/verify-gate-results.ps1`, `docs/VALIDATION.md`).
- **No validator bypass** and **no policy relaxation** without human approval.
- **Never** downgrade `fail` to `warn` in reporting (see `tools/os-autopilot.ps1` and `policies/autonomy-policy.json` → `validationRules`).
- **Never** claim success if a required validation was skipped or did not return `ok` for the orchestrated path.

## Positioning: upstream of CI/CD (rule 7)

Claude OS **raises the quality of what reaches** formal delivery — it is **not** a substitute for:

| Remains authoritative | Role |
|----------------------|------|
| **CI/CD pipelines** | Build, test, artifact, environment, promotion. |
| **GitHub Actions** (or equivalent) | Remote, reproducible execution of agreed commands. |
| **Production controls** | Runtime safety, access, monitoring, incident command. |
| **Human approval** | Critical risk transitions (see `requiresHumanApproval.surfaces` in `policies/autonomy-policy.json`). |

Read: `README.md` (“not a replacement for CI/CD”), `ARCHITECTURE.md` — *Operational positioning* / *What Claude OS is not*, `docs/POSICIONAMENTO-NAO-E.md` (PT).

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

Surface IDs: `requiresHumanApproval.surfaces` in **`policies/autonomy-policy.json`** — includes **production**, **release publish**, **deploy**, **destructive writes**, **migrations**, **RLS / auth / security** changes with runtime effect, incident actions with external impact, **secret handling**, **validator bypass**, **policy relaxation**, **breaking schema/manifest** changes, file removal, irreversible actions.

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

- `docs/VALUE-FOR-ENGINEERS.md` — seventeen concrete outcomes (continuity, autonomy vs micromanagement, gates, honest status, bootstrap, multi-tool, skills, pre-CI).
- `policies/invariants.md`, `invariants-manifest.json`, `docs/DEGRADED-MODES.md` — conservative laws (I-001–I-010), machine index, degraded status semantics.
- `docs/HAZARDS.md`, `docs/FMEA-LITE.md`, `docs/ASSURANCE-CASE.md`, `docs/WORKFLOW-STATES.md`, `docs/RISK-ENERGY.md`, `docs/REPO-BOUNDARIES.md` — hazards, failure modes, assurance, phased workflow, risk heuristic, and repo region boundaries.
- `playbooks/autonomous-repair.md` — runbook skeleton.
- `source/skills/autonomous-runtime/SKILL.md` — agent-facing procedure.
- `schemas/autonomy-policy.schema.json` — JSON Schema for the policy file.
- `pwsh ./tools/classify-change.ps1` — maps `(path, operationType, riskSurface)` → `autonomous` / `requiresApproval` / `requiredValidation` (uses `policies/autonomy-policy.json` steward surfaces); `-SelfTest` for CI-safe smoke.
- `pwsh ./tools/autonomous-commit-gate.ps1` — **local commit** evidence gate (`commitAllowed` / `pushAllowed`); requires `-ProposedCommitMessage` (human-supplied), `verify-no-secrets`, explicit `-TypecheckNotApplicable` or `-TypecheckCommand`, same for tests, scoped `git diff`, no touches under `policies/autonomous-commit-gated-paths.json`; **push** stays false unless `-StewardApprovedPush` + `-StewardPushReason`.
- `pwsh ./tools/verify-generated-drift.ps1` — canonical `source/skills/` vs manifest `generatedTargets` + `<!-- Generated from … -->` header contract; delegates `verify-skills-drift`; `-Strict` fails on drift/markers.
- `pwsh ./tools/sync-generated-targets.ps1` — `sync-skills` + `sync-agent-adapters` (ShouldProcess / `-WhatIf`).
- `pwsh ./tools/verify-manifest-graph.ps1` — cross-manifest dead paths, JSON↔schema pairs, capability/os-capabilities tool refs, distribution pack list, quality-gate scripts, release vs experimental/deprecated allowlist.
