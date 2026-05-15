# Claude OS assurance case (mini)

## Goal

**Claim → argument → evidence → known gaps.** Practical critical-systems language — not a certification artifact. Does **not** treat `warn` / `skip` / `skipped` / `unknown` / `degraded` / `blocked` / `not_run` as passed (**I-001**).

**Positioning:** Claude OS **improves** work **before** CI/CD; it does **not** replace **GitHub Actions**, **production controls**, or **human approval** at critical transitions (`README.md`, `ARCHITECTURE.md`, `policies/invariants.md`).

**Related:** `docs/HAZARDS.md`, `docs/WORKFLOW-STATES.md`, `docs/REPO-BOUNDARIES.md`, `docs/DEGRADED-MODES.md`, `policies/invariants.md`, `invariants-manifest.json`, `docs/VALIDATION.md`, `docs/AUTONOMY.md`.

---

## A1 — Claude OS prevents false green

### Argument

Orchestration and budgets exclude non-`ok` statuses from success semantics; autonomy JSON forbids silent downgrade of failures in reporting for governed paths.

### Evidence

- `policies/invariants.md` — **I-001**
- `runtime-budget.json` — `neverTreatAsPassed`
- `policies/autonomy-policy.json` — `validationRules`
- `tools/os-validate.ps1`, `docs/VALIDATION.md`, `examples/validation/`

### Known gaps

- Some legacy helpers may lack JSON envelopes; humans must not substitute narrative “green”.

---

## A2 — Claude OS supports high autonomy while gating critical transitions

### Argument

**L4** + matrix: read/list/search/inspect/analyze/report (and `git status`/`git diff`, typecheck/test/lint as **signal**) stay autonomous on any surface when read-only and no secrets. Writes to auth/RLS/migrations/secrets/deploy/release/destructive/policy relaxation stay **gated** with explicit approval paths.

### Evidence

- `.agent/operating-contract.md`, `policies/auto-approve-matrix.md`, `policies/autonomy-policy.json`
- `docs/AUTONOMY.md`, `docs/APPROVALS.md`

### Known gaps

- Session / classification discipline on edge tools until more paths are manifest-only.

---

## A3 — Claude OS keeps canonical and generated artifacts separated

### Argument

Canonical sources and manifests define truth; generated targets are derived and checked for drift; fixes flow **canonical → regenerate**, not “edit generated only”.

### Evidence

- `policies/invariants.md` — **I-002**, **I-003**
- `skills-manifest.json`, `tools/verify-skills-drift.ps1`, `docs/SKILLS.md`

### Known gaps

- Not every generated class may yet have a drift machine check.

---

## A4 — Claude OS preserves traceability from intent to validation

### Argument

Workflow phases forbid skipping **VALIDATE** before honest **CLOSE**; manifests and upgrade notes tie contract bumps to recorded intent; doc contract ties README/INDEX to real tools.

### Evidence

- `docs/WORKFLOW-STATES.md`, `upgrade-manifest.json`, `tools/verify-upgrade-notes.ps1`
- `verify-json-contracts`, `verify-doc-contract-consistency`, `policies/invariants.md` — **I-009**

### Known gaps

- Session-state intent fields only as good as operators/agents maintain them.

---

## A5 — Claude OS reports degraded modes honestly

### Argument

Missing Bash/Git/tests/schema/CI/session context produces **structured** `degraded` / `skip` / `blocked` / `warn` — not silent `ok` (**I-001**, `docs/DEGRADED-MODES.md`).

### Evidence

- `docs/DEGRADED-MODES.md`, `docs/VALIDATION.md`, `runtime-budget.json`
- `verify-os-health` / `os-validate` envelopes under `examples/validation/`

### Known gaps

- External dashboards may still mis-label unless aligned with envelopes.
- **Local** envelopes alone do not replace **authoritative** CI/CD green or org production policy.

---

## Use

- **Review:** use claims as checklist headings.  
- **Change:** if you weaken a control, update **argument / evidence / gaps** in the same change set or immediate follow-up.
