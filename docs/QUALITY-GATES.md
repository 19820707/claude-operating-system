# Manifest-governed quality gates

Quality gates are **JSON manifests** under **`quality-gates/`**. Each file describes how a class of work is proven: **required validators** (PowerShell tools only, under `tools/`), **allowed** vs **blocking** warnings, **required evidence**, **approval requirements**, **strict-mode behavior**, and (for release) **pass interpretation** so CI and humans do not treat non-`ok` outcomes as green.

| Gate file | Domain | Purpose |
|-----------|--------|---------|
| `quality-gates/docs.json` | docs | Docs index, manifest, doc-contract |
| `quality-gates/skills.json` | skills | Skills manifest, structure, body, drift |
| `quality-gates/release.json` | release | Structural gate registry + **strict** `os-validate` (includes `os-validate-all -Strict`) |
| `quality-gates/bootstrap.json` | bootstrap | Bootstrap manifest + bootstrap examples |
| `quality-gates/adapters.json` | adapters | Adapter templates + drift |
| `quality-gates/security.json` | security | Security policy, `.claudeignore`, critical-systems |

Schema: **`schemas/quality-gate.schema.json`**.

## Verifiers

- **`pwsh ./tools/verify-quality-gates.ps1`** — Confirms every expected gate file exists, JSON shape, scripts on disk, safe argument strings, and **release-only invariants** (see below). Wired into **`verify-json-contracts.ps1`**, **`verify-doc-contract-consistency.ps1`**, **`verify-os-health.ps1`**, and the **`quick`** profile of **`os-validate.ps1`** via `Run-JsonTool`.

- **`pwsh ./tools/evaluate-quality-gate.ps1 -Gate <domain> [-Strict] [-Json]`** — Runs the validators listed in the matching manifest and applies **blockingWarnings** / **allowedWarnings**. Use for pre-merge or local checks; release evaluation exits **non-zero** unless aggregate status is **`ok`**.

## Release false-green rule

`quality-gates/release.json` declares **`passInterpretation`**:

- **`onlyStatusOkIsPass`**: `true`
- **`statusesNeverEquivalentToPassed`**: `skip`, `warn`, `unknown`, `degraded`, `blocked`, `fail`
- **`nonPassStatusAliases`**: `skipped`, `not_run` (aligned with **`runtime-budget.json`** → `neverTreatAsPassed`)

`verify-quality-gates.ps1` **fails** if any of those statuses or aliases are missing from the manifest, so the release contract cannot silently rot.

## Status taxonomy

See **`docs/VALIDATION.md`**. Validator envelopes use **`schemas/os-validator-envelope.schema.json`** (`ok`, `warn`, `fail`, `skip`, `blocked`, `degraded`, `unknown`). The release gate treats only **`ok`** as pass when `passInterpretation` is present; **`evaluate-quality-gate.ps1`** also exits **1** on any aggregate **`warn`** for **`gate.release`**.

## Deprecations

**`deprecation-manifest.json`** governs deprecated scripts, skills, docs, manifest keys, and commands. **`pwsh ./tools/verify-deprecations.ps1 -Strict`** is part of **`quality-gates/release.json`**, **`os-validate -Profile strict`**, and **`verify-os-health`**. See **`policies/deprecation.md`**.

## Related

- **`docs/RELEASE-READINESS.md`** — operator checklist and evidence.
- **`docs/CAPABILITIES.md`** — intent routes vs fine-grained capabilities.
