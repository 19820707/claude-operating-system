# FMEA-lite (failure modes without bureaucracy)

Short failure-mode table for Claude OS: **failure mode → effect → severity → detection → mitigation**.  
Pairs with `docs/HAZARDS.md` (hazard-centric view). Severity is qualitative (Low / Medium / High / Critical) for prioritisation, not a formal safety integrity level.

**Related:** `docs/HAZARDS.md`, `docs/ASSURANCE-CASE.md`, `docs/WORKFLOW-STATES.md`, `docs/RISK-ENERGY.md`, `policies/invariants.md`, `docs/VALIDATION.md`, `docs/COMPATIBILITY.md`, `docs/QUALITY-GATES.md`.

## Failure mode table

| Failure mode | Effect | Severity | Detection | Mitigation |
|--------------|--------|----------|-----------|------------|
| Bash missing locally | Bash hooks or scripts not exercised on developer machine | Medium | `verify-os-health` / doctor-style checks | Allow local warn where policy says so; require CI strict path |
| Git checkout missing or dirty | Provenance and hygiene unknown | Medium | `verify-git-hygiene.ps1` | Warn locally; fail in strict; operator documents clean state before release |
| PowerShell version mismatch | Different behaviour PS 5.1 vs `pwsh` | Medium | `verify-compatibility.ps1`, docs | Document supported matrix; CI uses same shell as release |
| Adapter or generated skill drift | Agents receive different instructions than repo intent | High | `verify-skills-drift`, adapter drift checks, sync playbooks | Sync from canonical `source/`; block strict until clean |
| Validator skipped in CI | False confidence in artifact quality | Critical | CI config review; envelope must list checks | Never treat skipped as passed (I-001); fix pipeline |
| `neverTreatAsPassed` misconfigured | Warn or degraded treated as success | Critical | `verify-autonomy-policy`, `verify-runtime-budget` | Restore conservative defaults; re-run full strict |
| Policy relaxation unapproved | Weakened gates for autonomy or release | Critical | Operating contract audit; PR review | Require human approval and record (I-007, I-008) |
| Secret pattern in new file type | Secret reaches remote | Critical | Extend `verify-no-secrets` coverage; review | Rotate secret; add detector; redact templates |
| Schema bump without notes | Downstream tools break silently | High | `verify-upgrade-notes.ps1` | Add migration note + version bump (I-009) |
| Experimental component on strict path | Release built on immature surface | High | `verify-components.ps1` | Remove dependency or graduate component with evidence |

## When to extend the table

Add a row when postmortem or review finds a **recurring** class of failure not already covered. Prefer linking the mitigation to a **script or manifest** change so the next run fails closed instead of relying on memory.
