# Invariantes — leis conservativas (Claude OS)

## Non-negotiable operational invariants

Operational laws that **no** repo change or agent flow may violate — including autonomous work. Verification is primarily **machine** (scripts + manifests); human process fills gaps without weakening gates.

| Theme | Requirement |
|-------|-------------|
| **No false green** | `warn` / **`skipped`** / `unknown` / `degraded` / `blocked` / `not_run` **never** count as *passed*; treat envelope token **`skip`** the same way when present — align with `neverTreatAsPassed` and JSON envelopes. |
| **Read-only autonomous** | `read` / `list` / `search` / `inspect` / `analyze` / `report` on **any** surface (including auth, RLS, migrations, billing, CI, production-adjacent files) **without** mutation or secret handling — no extra human micro-confirmation (L4). |
| **Generated artifacts are not canonical** | Adapters and synced copies (e.g. `.claude/`, `.cursor/`) are **derived**; truth is `source/` + manifests. |
| **Critical transitions require approval** | **Production**, **release**, **deploy**, **applied migrations**, **RLS / auth / security** changes with runtime effect, **secrets**, **destructive** writes, **policy / gate relaxation**, **validator bypass**, **breaking schema/manifest** changes → explicit **human** approval + auditable record where required (**I-007**, **I-008**). |
| **Autonomous writes** (when allowed by matrix) | Must be **scoped**, **reversible**, **diff-visible**, and followed by **validation** at agreed profile semantics — see `policies/auto-approve-matrix.md` column 2. |
| **No secrets in logs / context / templates / examples** | No credentials in tracked logs, examples, repo context files, or versioned templates (**I-010**). |
| **Schema / manifest traceability** | Central JSON contracts change with compatible **schemaVersion bump** and/or **migration note** where the repo requires it; strict/release does not silently rest on **experimental** components without an approved path (**I-004**, **I-009**). |
| **Upstream of CI/CD — not a substitute** | Claude OS **improves** local/agent work **before** it reaches formal pipelines; it does **not** replace **CI/CD**, **GitHub Actions**, **production controls**, or **human approval** at critical risk transitions (`README.md`, `ARCHITECTURE.md`, `docs/AUTONOMY.md`). |

> Pairs with `policies/autonomy-policy.json`, `policies/auto-approve-matrix.md`, `.agent/operating-contract.md`, `runtime-budget.json` (`neverTreatAsPassed`), `gate-status-contract.json` (canonical status vocabulary), and `pwsh ./tools/verify-gate-results.ps1` (drift guard across budget, release gate, envelope schema). Machine index: `invariants-manifest.json`. **Violation:** governance defect — revert, fix policy/validator/manifest, re-validate.

| ID | Invariant | Operational implication |
|----|-----------|-------------------------|
| **I-001** | Non-`ok` statuses above **never** count as *passed*. | Envelopes and summaries match `neverTreatAsPassed` and `gate-status-contract.json`; `verify-gate-results` catches enum / gate drift; no cosmetic green. |
| **I-002** | Generated adapter/copy is **never** canonical source. | Regenerate from `source/` + manifests. |
| **I-003** | Every declared **generated target** has explicit **canonical** source in manifest. | Drift without source = contract defect; `verify-skills-drift` / sync. |
| **I-004** | **strict** / **release** must not depend on **experimental** / **deprecated** without approved path. | `verify-components`, `verify-compatibility`. |
| **I-005** | Autonomous **write** requires **reversibility** or **rollback**. | See `policies/auto-approve-matrix.md`, `playbooks/autonomous-repair.md`. |
| **I-006** | **Read-only** autonomous on critical surfaces (no mutation, no secrets). | `.agent/operating-contract.md` L4. |
| **I-007** | Production / release / applied migration / secrets / destructive → **human approval**. | `policies/autonomy-policy.json` → `requiresHumanApproval.surfaces`; `docs/APPROVALS.md`. |
| **I-008** | Policy or gate **relaxation** → **human approval** + **record**. | No silent widen of `neverTreatAsPassed` or validator bypass. |
| **I-009** | Schema / central manifest change → **bump** or **migration note** where required. | `upgrade-manifest.json`, `verify-upgrade-notes`. |
| **I-010** | **No secrets** in logs, examples, repo context, versioned templates. | `verify-no-secrets`, `safe-output.ps1` patterns. |

## Cross-read

`docs/HAZARDS.md`, `docs/FMEA-LITE.md`, `docs/ASSURANCE-CASE.md`, `docs/WORKFLOW-STATES.md`, `docs/RISK-ENERGY.md`, `docs/REPO-BOUNDARIES.md`, `docs/DEGRADED-MODES.md`, `docs/VALIDATION.md`, `docs/AUTONOMY.md`.

## Design note

Do **not** weaken **I-001** or **I-007–I-008** when adding convenience; autonomy stays high only where the matrix and contract say it may. **Local green is not production green** until the same contracts pass in your **authoritative** CI/CD and steward process says so.
