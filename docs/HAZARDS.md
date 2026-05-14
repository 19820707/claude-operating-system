# Claude OS hazard register

## Goal

Lightweight **hazard → cause → control → evidence → residual risk** register (≤ **20** rows). Complements `policies/auto-approve-matrix.md` and `policies/invariants.md` — not a formal STPA/FMEA import.

**Related:** `docs/ASSURANCE-CASE.md`, `docs/WORKFLOW-STATES.md`, `docs/REPO-BOUNDARIES.md`, `docs/DEGRADED-MODES.md`, `policies/invariants.md`, `docs/VALIDATION.md`, `.agent/operating-contract.md`.

## Register

| ID | Hazard | Cause | Control | Evidence | Residual risk |
|----|--------|-------|---------|----------|---------------|
| H-001 | **False green** on merge or release | Wrappers treat `warn` / `skip` or `skipped` / `unknown` / `degraded` / `blocked` / `not_run` as success | **I-001**, `neverTreatAsPassed`, `os-validate` aggregation | JSON envelopes; `runtime-budget.json` | Bad aggregator or manual summary |
| H-002 | **Adapter / skill drift** from canonical | Skipped sync; manual edit in generated tree | **I-002**/**I-003**, drift verifiers, sync playbooks | `verify-skills-drift` (and adapter checks where wired) | Drift unnoticed until strict CI |
| H-003 | **Missing Git** context | Not a checkout; broken `.git` | `verify-git-hygiene`, docs | Hygiene verifier output | False provenance assumptions |
| H-004 | **Missing Bash** locally | Windows PATH gaps | compatibility matrix, health with honest `skip`/`degraded` | `docs/COMPATIBILITY.md`, envelopes | Shell-only bugs found late |
| H-005 | **Policy relaxation** without trace | Urgency; “just this once” | **I-008**, PR + approval record | `docs/APPROVALS.md`, PR text | Verbal-only OK |
| H-006 | **Secrets leakage** into repo | Paste into examples/templates | `verify-no-secrets`, `SECURITY-LINT` | Lint / CI logs | Novel secret shapes evade patterns |
| H-007 | **Autonomous write without rollback** | Rushed APPLY | **I-005**, matrix col 2, session rollback field | session-state; git history | Partial revert / data loss |
| H-008 | **Release without strict validation** | Short CI; wrong profile | strict profile, quality-gates | `os-validate -Profile strict` artifacts | Misconfigured pipeline |
| H-009 | **Critical read-only audit over-gated** | “Critical” misread as “no agent” | **I-006**, L4 contract | `.agent/operating-contract.md` | Slower audits; shadow IT |
| H-010 | **Generated artifact edited manually** as truth | Fork from canonical | regenerate path, drift checks | `skills-manifest.json`, drift output | Two sources of “truth” |
| H-011 | Production **migration** without human gate | Autopilot | **I-007**, autonomy surfaces | `policies/autonomy-policy.json` | Wrong target DB |
| H-012 | **Schema/manifest bump undocumented** | Drive-by JSON edit | **I-009**, `verify-upgrade-notes` | `upgrade-manifest.json` | Silent consumer break |
| H-013 | **Validator skipped** in CI | YAML mistake | neverTreatAsPassed + review | CI config | False confidence |
| H-014 | **Strict** depends on **experimental** tool | Bad component tier | **I-004**, `verify-components` | component report | “Strict on sand” |
| H-015 | **Steward playbook** without ledger | Process slip | `verify-approval-log` where required | `logs/approval-log.jsonl` | Unaudited steward action |
| H-016 | **Doc/manifest contract drift** | Renamed script not reflected | `verify-doc-contract-consistency` | verifier JSON | Operators run wrong commands |
| H-017 | **Claude OS mistaken for CI/CD / production authority** | Marketing or lazy docs | `README.md`, `ARCHITECTURE.md`, `docs/AUTONOMY.md`, positioning row in `policies/invariants.md` | Architecture + autonomy docs | Teams skip real pipelines or approvals |

## Use

1. Prefer **adding a control** (validator, manifest) over prose-only process.  
2. New failure class: add a row **if** not already covered (keep ≤ 20).  
3. On control failure: **revert**, **rotate secrets**, **freeze** merge, or **escalate** — pick one concretely.
