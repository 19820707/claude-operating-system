# Operating modes policy (Claude Code)

**Purpose:** Same contract as Cursor rule `06-operating-modes.mdc` — when to run **fast** vs **phase-close** vs **critical** vs **production**.

## Baseline phrase
**High autonomy with gates in the right place.**

## Modes (summary)

| Mode | Use | Claude | Model | Machine truth |
|------|-----|--------|-------|----------------|
| **Fast** | Daily implementation | Read/discover, additive schema/migrations, docs, allowed Bash from `settings.json` | Sonnet 4.6 (Haiku for search) | Optional short checks |
| **Phase** | End of slice before merge | Final narrative: risk + rollback | Opus 4.6 | **`scripts/validation/validate.ps1`**, `verify:local` when required |
| **Critical** | Auth/authz, payments, non-additive migrations, sensitive data, prod-touching infra | Plan first; narrow “Accept all”; no silent scope expansion | **Opus 4.6 mandatory** | Domain gates (security, contracts, targeted e2e) |
| **Production** | Deploy, stores, GO declaration | Preparation only — checklists, PRs, evidence | **Opus 4.6 mandatory** | CI + runbooks; **human approval required** per `production-safety.md` |

Model selection rules and task → model mapping: see `model-selection.md`.

## Transitions
- Default session: **Fast**.
- Before phase close: escalate to **Phase** (heavy validate + explicit rollback note).
- On sensitive surfaces: jump to **Critical** immediately.
- Anything live or store-facing: **Production** only.

## Do not
Downshift from **Critical**/**Production** to **Fast** without confirming residual risk is gone.
