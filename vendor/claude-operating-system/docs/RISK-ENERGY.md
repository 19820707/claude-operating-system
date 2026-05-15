# Risk energy (operational metaphor, not numerics)

A lightweight way to discuss **accumulated risk** from validation and governance signals without pretending exact science. Use it to compare **before/after** a change set or to gate **merge/release** discussion — not as a substitute for human judgment on novel failures.

**Related:** `docs/WORKFLOW-STATES.md`, `docs/HAZARDS.md`, `docs/FMEA-LITE.md`, `docs/VALIDATION.md`, `runtime-budget.json`, `policies/invariants.md`.

## A. Conserved quantities (metaphor)

Treat these as **bookkeeping invariants**: if one changes, linked artifacts and statuses must move in a coherent way or the system is in an inconsistent (high-risk) state.

| Quantity | Practical meaning in Claude OS |
|----------|--------------------------------|
| **Canonical skills count** | Skills under canonical `source/` and `skills-manifest.json` — adding one requires manifest + sync + drift checks. |
| **Generated targets count** | Declared `generatedTargets` (and similar) must match what validators expect after sync. |
| **Schema references** | JSON under `schemas/` referenced by manifests and tools — if a schema is removed, no manifest should still reference it (contract tests / JSON validators). |
| **Manifest references** | Paths in `bootstrap-manifest.json`, `component-manifest.json`, `quality-gates/*.json`, etc. — must resolve and stay internally consistent. |
| **Validation statuses** | Envelope `status` fields aggregated per `neverTreatAsPassed` — cannot silently “conserve” a fail as pass. |
| **Risk gates** | Gates required for strict/release in `os-validate`, `verify-os-health`, quality gates — removing a gate from disk without updating profiles leaves release undefined. |

When any of these drifts, **repair** (with approval if needed) then **revalidate** per `docs/WORKFLOW-STATES.md`.

## B. Risk energy (simple score)

A **ordinal / heuristic** score for prioritisation only. Tune coefficients and threshold to your team; the point is a **shared vocabulary**, not calibration to physical units.

```text
riskEnergy =
    criticalFailures * 100
  + highFailures       * 50
  + warnings           * 10
  + driftFindings      * 15
  + skippedChecks      * 25
  + unvalidatedWrites  * 40
```

**Suggested definitions (tune in your process):**

- **criticalFailures** — validator `fail` on a release/steward-class check, or I-007/I-008 violation.  
- **highFailures** — `fail` on non-steward checks, or structural manifest/schema break.  
- **warnings** — counts of `warn` that your policy still ships for merge (discouraged on strict paths).  
- **driftFindings** — output lines or structured findings from drift verifiers (skills, adapters, docs index).  
- **skippedChecks** — checks that did not run but were required for the profile.  
- **unvalidatedWrites** — APPLY without subsequent VALIDATE / REVALIDATE (workflow violation).

### Merge / release rule (example)

```text
merge or release only if riskEnergy < threshold
```

Choose **threshold** conservatively (for example `0` for release: no failures, no skips, no unvalidated writes). For merge to main with intermediate posture, you might allow bounded warnings if **explicitly** documented and still consistent with I-001.

### Honesty clause

- Coefficients are **not** derived from reliability physics; changing tooling changes counts.  
- Do not use risk energy to **override** I-001 or human gates — only to **summarise** and **sort** work.

## Future automation

When it pays off, a script such as `tools/calculate-risk-energy.ps1` could parse latest `os-validate -Json` envelopes and drift tool JSON to emit a single number and pass/fail against threshold. **Not required** for the metaphor to be useful; document and align behaviour first.
