# Operating Modes Policy

**Purpose:** Define when and how to operate — model, approval posture, validation gate — by mode.

**Baseline:** High autonomy with gates in the right place.

---

## Modes

| Mode | Use | Model | Approval | Validation gate |
|------|-----|-------|----------|-----------------|
| **Explore** | Discovery, mapping, reading — no edits | Haiku / Sonnet | None | None — read-only |
| **Fast** | Docs, templates, bootstrap, scripts, session-state, learning-log | Sonnet | Auto-accept permitted | Optional short checks |
| **Build** | Implementation, wiring, tests, refactor, adapters, observability | Sonnet | Manual or semi-manual | typecheck + target tests |
| **Review** | Architecture assessment, risk mapping, release readiness, go/no-go | Opus | Manual — propose before edit | Evidence required |
| **Critical** | Auth, authz, entitlements, billing, publish flow, security invariants | **Opus mandatory** | Manual — plan first, narrow accept | Domain gates + security checks |
| **Production-safe** | Pre-deploy hardening, runbooks, checklist verification | **Opus mandatory** | Manual — checklist driven | CI green + rollback defined |
| **Incident** | Active production failures, elevated error rate, security events | **Opus mandatory** | Manual — stabilise before investigating | Evidence before hypothesis |
| **Migration** | Schema changes — additive or destructive | **Opus mandatory** | Manual — staging run required | Down migration required |
| **Release** | Release candidate validation, go/no-go declaration | **Opus mandatory** | Manual — human gate for deploy | Full validation suite + rollback |

---

## Risk → Mode mapping

| Risk level | Surface examples | Mode | Model |
|-----------|-----------------|------|-------|
| **Low** | docs, templates, bootstrap, scripts, knowledge, learning-log, session-state | Fast | Sonnet |
| **Medium** | new contracts, local refactor, wiring, adapters, tests | Build | Sonnet |
| **High** | boundaries, sensitive integrations, central flows, architectural changes | Review → Build | Opus decides / Sonnet executes |
| **Critical** | auth, billing, payments, deploy, destructive migrations, publish flow, security invariants | Critical / Migration / Release | Opus mandatory |

---

## Transitions

- Default session: **Fast**.
- Any new implementation: escalate to **Build**.
- Any architectural decision: escalate to **Review** (Opus).
- On any critical surface: jump to **Critical** immediately. No downshift without confirming residual risk is gone.
- Active incident: jump to **Incident** immediately.
- Schema change: jump to **Migration** immediately.
- Pre-deploy: **Production-safe** then **Release**.

---

## Approval strategy by mode

| Mode | Strategy |
|------|----------|
| Explore / Fast | Auto-accept permitted |
| Build | Manual or semi-manual depending on surface |
| Review | Manual — proposal before any edit |
| Critical / Migration / Release / Incident / Production-safe | Manual always. Never auto-accept. |

---

## Do not

- Downshift from Critical/Migration/Release/Incident without confirmed residual risk gone
- Use auto-accept on any critical surface
- Declare **Release** GO without defining rollback
- Enter **Incident** mode and touch production before explicit human approval
- Bundle Critical + Fast work in the same phase

---

## Tool role by mode

| Tool | Role |
|------|------|
| **Claude Code** | Discovery, architecture, risk classification, contracts, plan, validation, synthesis, rollback, decision |
| **Cursor** | Visual editing, file navigation, diff review, local refactor, immediate feedback |
| **Claude OS** | Persistent context, session continuity, policies, heuristics, model selection, learning loop, governance |

Model selection rules and task → model mapping: see `model-selection.md`.
