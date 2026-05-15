<!-- Generated from source/skills/autonomous-runtime/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/autonomous-runtime/SKILL.md. -->
---
name: autonomous-runtime
description: "Use when running bounded autonomous validation loops (A3) with dry-run, diff, evidence, and mandatory human gates for steward transitions."
category: verification
version: 1.0.0
user-invocable: true
---

# Autonomous runtime (A3)

## Purpose

Operate agents under **A3 — autonomous with gates**: maximize safe automation for **reversible** engineering tasks while refusing **A4** closed-loop control on critical surfaces.

## Non-goals

- Unsupervised production changes, CI replacement, or validator bypass.
- Treating `warn` / `skip` / `unknown` / `degraded` / `blocked` as pass.

## Inputs

- Goal text, validation profile (`quick` | `standard` | `strict`), autonomy level (default **A3**), dry-run preference.

## Outputs

- Structured autopilot JSON (`tools/os-autopilot.ps1 -Json`).
- Optional JSONL evidence line (`-WriteEvidence`).

## Operating mode

- Default autonomy: **A3** for low/medium reversible tasks.
- **A4** is **forbidden** for steward-class goals; autopilot will **block**.
- Human approval is required for transitions listed in `policies/autonomy-policy.json` → `requiresHumanApproval.surfaces`.

## Procedure

1. Read `policies/autonomy.md` and `docs/AUTONOMY.md`.
2. Run `pwsh ./tools/verify-autonomy-policy.ps1 -Json` (add `-Strict` before release-sensitive work).
3. Run `pwsh ./tools/os-autopilot.ps1 -Goal "..." -Profile quick -DryRun -Json` first; remove `-DryRun` only when writes are explicitly in scope and governed.
4. Never publish releases or mutate production without `docs/APPROVALS.md` / ledger requirements.

## Validation

- If any validation envelope is not `ok`, do not claim overall success.
- Re-run deeper profiles only when justified and documented.

## Failure modes

- False green from mis-read `warn`/`skip`.
- Goal text accidentally triggers steward escalation (treat as **blocked**, not silent pass).

## Safety rules

- No secrets in logs; use redaction discipline.
- No validator bypass; no silent policy relaxation.
- Prefer branch + diff + rollback plan.

## Examples

- See `examples/skills/autonomous-runtime.md`.

## Related files

- `policies/autonomy-policy.json`, `schemas/autonomy-policy.schema.json`, `tools/os-autopilot.ps1`, `playbooks/autonomous-repair.md`
