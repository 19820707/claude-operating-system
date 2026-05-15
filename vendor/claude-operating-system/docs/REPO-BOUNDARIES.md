# Repository field boundaries

## Goal

Map **repo regions** → default **risk**, **autonomous actions**, **gated actions**, **required validation**. Use before large edits; does **not** replace `policies/auto-approve-matrix.md` or **I-001**. **CI/CD and production controls** remain authoritative for their domains (`README.md`, `ARCHITECTURE.md`).

**Related:** `docs/WORKFLOW-STATES.md`, `docs/HAZARDS.md`, `playbooks/docs-contract-audit.md`, `docs/VALIDATION.md`, `policies/invariants.md`, `.agent/operating-contract.md`.

## Region map

| Region | Risk | Autonomous actions | Gated actions | Required validation |
|--------|------|--------------------|---------------|------------------------|
| **`docs/`** | low / medium | Read; doc edits that **do not** weaken safety/validation claims | Rewording release/CI/safety promises without review | `verify-doc-contract-consistency`, `verify-doc-manifest`, `verify-docs-index` when index/counts touched |
| **`policies/`** | high | Read; draft text in branch without merge | Relaxing gates, `neverTreatAsPassed`, autonomy surfaces (**I-007**, **I-008**) | Doc contract audit + `os-validate` (≥ **standard**, **strict** near release) |
| **`schemas/`** | high | Read | Breaking JSON Schema or shape consumers rely on | `verify-json-contracts`; `verify-upgrade-notes` when bumping watched contracts |
| **`tools/`** | medium / high | Read; run tools locally read-only | Mutating installers, unsafe `writeRisk` paths | `verify-script-manifest`; exercise changed tools in profile; contract tests where wired |
| **`templates/`** | medium / high | Read | Changing default agent/command/hook behaviour affecting new projects | `verify-bootstrap-manifest`; `docs/PROJECT-BOOTSTRAP.md` expectations |
| **`source/skills/`** | high | Read; analyze capability text | Declaring new steward-facing behaviour without review | `verify-skills`, `verify-skills-structure`, `verify-skills-manifest`; post-sync drift checks |
| **`.agent/`** | high | Read | Changing L4/L7 shared contract without visibility | Doc contract + autonomy coherence review |
| **`.claude/`** (in **this** repo or **generated** in target projects) | medium / high | Read generated copy to audit drift | Treating generated tree as canonical edit surface (**I-002**) | Drift + sync from canonical; `init-project` / bootstrap checks when templates change |
| **`supabase/`** (when present in a consuming project) | **critical** | Read SQL/migrations as text; plan | **Apply** migrations to shared/prod; toggle RLS off | Migration review, order, rollback story; human approval |
| **Deployment config** (e.g. `.github/workflows/` deploy jobs, `Dockerfile`, `fly.toml`, Kustomize, env-specific Helm) | high | Read; lint static config if non-secret | **Publish** credentials; **auto-deploy** to prod; weaken approval gates in workflow | CI review + `os-validate` / org policy; secrets never in plaintext tracked files |

## Notes

- **Claude OS core** may not ship `supabase/`; the row defines **expected** behaviour when composed with Supabase.  
- **`.claude/`** in a **bootstrapped project** is generated/synced — same **canonical vs generated** rules as adapters.  
- **Escalate** when unsure if an edit is autonomous — default **fail-closed** on steward ambiguity.
