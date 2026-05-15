# Claude OS skills system

## What skills are

Skills are **operational contracts** for agents: when to use a workflow, what inputs and outputs to expect, safety rules, and how to validate results. They are plain Markdown with YAML frontmatter, stored canonically under `source/skills/<id>/SKILL.md`, and mirrored to tool-specific trees for bootstrap.

## Canonical source

- **Canonical root:** `source/skills/`
- **Manifest:** `skills-manifest.json` (each skill declares `path`, `maturity`, `riskLevel`, `contextBudget`, `generatedTargets`, `allowedAgents`, policies, examples, and tests or an exemption).

## Generated targets

Paths listed under `generatedTargets` in the manifest (for example `.claude/skills/<id>/SKILL.md` and `.cursor/skills/<id>/SKILL.md`) are **copies only**. Do not edit them by hand; change the canonical file and run sync.

## Sync

```powershell
pwsh ./tools/sync-skills.ps1 -DryRun -Json   # plan
pwsh ./tools/sync-skills.ps1 -Json          # apply (writes declared targets)
```

Generated files include an HTML comment header pointing at the canonical path. Drift checks strip that header before comparing body text to the canonical file.

## Validation

| Script | Role |
|--------|------|
| `tools/verify-skills-manifest.ps1` | JSON manifest vs schema, paths, policies, examples/tests or exemptions, risk gates; disk `source/skills/*` must match manifest ids; **`-Strict`** turns deprecated-in-release hits into failures |
| `tools/verify-skills-structure.ps1` | Required `SKILL.md` sections; stable **high/critical** must include explicit `## Safety rules`; **`-Strict`** fails any missing section on **stable** skills |
| `tools/verify-skills-economy.ps1` | Context budget, hygiene heuristics, and **rejects false-green phrasing** (for example `skipped = passed`, `warn = pass`) in canonical `SKILL.md` |
| `tools/verify-skills-drift.ps1` | Canonical vs generated copies; **`-Strict`** fails on body drift **or** missing generated files |
| `tools/verify-skills.ps1` | Directory count vs `bootstrap-manifest.json`, frontmatter, safe links |

**Profiles:** `tools/os-validate.ps1` runs manifest + structure + `verify-skills` on **quick**; adds economy + drift on **standard**; **strict** adds **`-Strict`** to manifest, structure, and drift (per `verify-os-health -Strict` as well).

## Maturity and status

- **maturity:** `stable`, `experimental`, `internal`, or `deprecated`
- **status:** `active`, `draft`, or `deprecated`

Deprecated skills must not appear enabled in release-style runtime profiles (see manifest `releaseProfileIds` and `verify-skills-manifest.ps1`). Experimental skills should stay off critical default surfaces until promoted.

## Risk and approval

- **riskLevel:** `low`, `medium`, `high`, or `critical`
- **high** and **critical** skills must declare a non-empty `requiresApprovalFor` array in the manifest.

Human approval is required for release and production-affecting work as spelled out in each skill’s **Operating mode** and in `policies/production-safety.md`.

## Context budgets

Each skill declares `contextBudget.maxLines` and `contextBudget.maxBytes`. `verify-skills-economy.ps1` enforces those limits on canonical `SKILL.md` files. Keep skills concise; push long reference material to `examples/skills/` or policies.

## Adding a skill

1. Add `source/skills/<id>/SKILL.md` using `templates/skills/SKILL.template.md`.
2. Add an entry to `skills-manifest.json` (unique `id`, valid `path`, `generatedTargets`, `contextBudget`, `allowedAgents`, `maturity`, `riskLevel`, `requiresApprovalFor` when high/critical, examples/tests or `examplesExemptionReason`).
3. Bump `bootstrap-manifest.json` `skills.exact` and `repoIntegrity.source/skills.exact`, and extend `projectBootstrap.criticalPaths` for each `.claude/skills/<id>/SKILL.md` you require at bootstrap.
4. Register new tools in `script-manifest.json` if you add validators or sync scripts.
5. Run `pwsh ./tools/sync-skills.ps1 -Json` and re-run drift validators.

## Deprecating a skill

1. Set `maturity` to `deprecated` and `status` to `deprecated` in `skills-manifest.json`.
2. Remove or gate references in profiles, docs, and bootstrap critical paths after consumers migrate.
3. Keep generated copies in sync until removal is complete; then delete canonical and manifest rows and shrink bootstrap counts.

## Skill index

| Skill | Maturity | Risk | Purpose | Canonical path | Agents |
|-------|----------|------|---------|----------------|--------|
| bootstrap-governance | stable | medium | Bootstrap and manifest governance | `source/skills/bootstrap-governance/SKILL.md` | claude, cursor, codex |
| production-safety | stable | critical | Production, secrets, no false green | `source/skills/production-safety/SKILL.md` | claude, cursor, codex |
| token-economy | stable | medium | Context and validation cost control | `source/skills/token-economy/SKILL.md` | claude, cursor, codex |
| invariant-engineering | stable | high | Invariants and verification gates | `source/skills/invariant-engineering/SKILL.md` | claude, cursor, codex |
| multi-agent-coordination | stable | high | Multi-agent coordination | `source/skills/multi-agent-coordination/SKILL.md` | claude, cursor, codex |
| epistemic-discipline | stable | medium | Evidence quality and honest unknowns | `source/skills/epistemic-discipline/SKILL.md` | claude, cursor, codex |
| runtime-economy | stable | medium | Cheapest sufficient validation path | `source/skills/runtime-economy/SKILL.md` | claude, cursor, codex |
| release-readiness | stable | critical | Release gate checklist and residual risk | `source/skills/release-readiness/SKILL.md` | claude, cursor, codex |
| adapter-drift | stable | high | Canonical vs generated adapter copies | `source/skills/adapter-drift/SKILL.md` | claude, cursor, codex |
| doc-contract-audit | stable | medium | Docs and manifest contract alignment | `source/skills/doc-contract-audit/SKILL.md` | claude, cursor, codex |
| incident-safe-change | stable | critical | Incident-time minimal safe change | `source/skills/incident-safe-change/SKILL.md` | claude, cursor, codex |

## Intentional exemptions

Legacy skills (`bootstrap-governance`, `production-safety`, `token-economy`, `invariant-engineering`, `multi-agent-coordination`, `epistemic-discipline`) use `examplesExemptionReason` in `skills-manifest.json` until examples and JSON tests are split out of the main `SKILL.md` body.

## Schema

- `schemas/skills-manifest.schema.json` describes `skills-manifest.json`.
- `os-manifest.json` references the skills manifest via `manifests.skillsManifest`.

No third-party product–specific workflows were imported into these skills; patterns are limited to generic engineering, validation, and adapter hygiene.
