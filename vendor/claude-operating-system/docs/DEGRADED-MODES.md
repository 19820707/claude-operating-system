# Degraded modes (honest partial failure)

## Goal

When dependencies are missing or quality is partial, emit **structured** status (`degraded`, `warn`, `skip` / **`skipped`**, `blocked`, `unknown`, `not_run`) — **never** pretend **ok** for merge/release (**I-001**, `neverTreatAsPassed`). Does **not** weaken autonomy for **read-only** work (**I-006**).

**Related:** `docs/VALIDATION.md`, `policies/invariants.md`, `runtime-budget.json`, `docs/WORKFLOW-STATES.md`, `docs/ASSURANCE-CASE.md` (A5).

## Status recap

| Status | Meaning |
|--------|---------|
| `ok` | Check succeeded per contract. |
| `warn` / `skip` or `skipped` / `unknown` / `degraded` / `blocked` / `not_run` | **Not** “pass” for conservative release unless explicit **I-008** exception + record. |

---

## Bash unavailable

| | |
|---|--|
| **Impact** | Bash hooks / `bash -n` may not run locally; shell coverage gap. |
| **Allowed autonomous actions** | Read hook sources; PowerShell-only checks; document PATH. |
| **Blocked actions** | Claim strict parity on this host; merge treating skipped bash as `ok`. |
| **Remediation** | Install Git Bash / WSL; run strict in CI with Bash on path. |
| **Strict behaviour** | Envelopes stay non-`ok` or explicitly `skip`/`degraded` — **not** upgraded to success. |

---

## Git unavailable

| | |
|---|--|
| **Impact** | Hygiene / provenance weaker; `verify-git-hygiene` may warn or skip. |
| **Allowed autonomous actions** | Read tree as files; non-git validators. |
| **Blocked actions** | Autonomous `commit`/`push` story; claim clean history without git evidence. |
| **Remediation** | `git clone` or `git init`; re-run hygiene in standard/strict. |
| **Strict behaviour** | Gates that require git metadata fail or block — not silent `ok`. |

---

## Tests unavailable

| | |
|---|--|
| **Impact** | Test-backed guarantees not re-run; logic drift risk. |
| **Allowed autonomous actions** | Lint/manifest/static checks still allowed; read-only review. |
| **Blocked actions** | Mark merge green while required tests did not run or failed. |
| **Remediation** | Fix runner, packages, filters; restore CI job. |
| **Strict behaviour** | Required tests must be **`ok`** for strict/release interpretation. |

---

## Schema validation unavailable

| | |
|---|--|
| **Impact** | Manifest ↔ schema pairs not verified this run. |
| **Allowed autonomous actions** | Read JSON; postpone contract-changing edits. |
| **Blocked actions** | Merge manifest edits “because verifier crashed”. |
| **Remediation** | Fix `pwsh` / paths; run `verify-json-contracts` in CI. |
| **Strict behaviour** | Treat verifier failure as **fail** or **blocked**, not `ok`. |

---

## Adapter drift present

| | |
|---|--|
| **Impact** | Generated adapters/skills differ from canonical; agents see wrong instructions. |
| **Allowed autonomous actions** | Read canonical `source/skills`; plan governed sync. |
| **Blocked actions** | Edit generated tree as authority; close as success while drift checks fail. |
| **Remediation** | Run `sync-skills` (or equivalent); `verify-skills-drift` clean. |
| **Strict behaviour** | Drift verifiers **fail** strict when policy requires zero drift. |

---

## Stale or missing session state

| | |
|---|--|
| **Impact** | Intent, surfaces, rollback notes absent or outdated — harder audit; **does not** remove gates on writes. |
| **Allowed autonomous actions** | Read-only discovery; refresh session template with current intent/surfaces. |
| **Blocked actions** | Use “stale session” as excuse to skip human gates on steward writes. |
| **Remediation** | Populate or update `.claude/session-state.md` (or project equivalent) per playbook. |
| **Strict behaviour** | Stale/missing state is **not** a bypass; validators and matrix still apply. |

---

## Unknown validator result

| | |
|---|--|
| **Impact** | A verifier returns **`unknown`**, empty status, or malformed envelope — outcome not provable. |
| **Allowed autonomous actions** | Re-run the tool with `-Json`; capture raw output; read-only triage of script/version. |
| **Blocked actions** | Treating **`unknown`** as **`ok`** for merge/release; hiding the ambiguity in summaries. |
| **Remediation** | Fix verifier bug; pin tool version; extend schema/examples for the tool’s envelope. |
| **Strict behaviour** | **`unknown`** stays non-passing until investigated (**I-001**); prefer **ESCALATE** over dishonest **CLOSE** (`docs/WORKFLOW-STATES.md`). |

---

## CI unavailable

| | |
|---|--|
| **Impact** | No second-machine verification; higher merge risk. |
| **Allowed autonomous actions** | Local `os-validate` / `verify-os-health`; save JSON envelopes as evidence; **delay** merge. |
| **Blocked actions** | Release or deploy on “laptop only” without CI replay (unless recorded **I-008** exception). |
| **Remediation** | Retry queue; mirror workflow; partial matrix with honest non-`ok` if incomplete. |
| **Strict behaviour** | Release policy expects CI-green or steward exception on record. |

---

## Agent rules (all modes)

1. Never map `degraded`/`warn`/`skip` → `ok` without **I-008**.  
2. **WORKFLOW-STATES:** no **CLOSE** as success on non-`ok` aggregates.  
3. Prefer structured envelopes over prose-only status.
