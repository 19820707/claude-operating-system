# Contract tests

Contract tests enforce **cross-surface consistency**: manifests, documentation, and PowerShell tooling must agree so CI and strict profiles do not drift into false greens.

## Run

From the repository root:

```powershell
pwsh ./tools/run-contract-tests.ps1
```

Machine-readable summary (validator envelope):

```powershell
pwsh ./tools/run-contract-tests.ps1 -Json
```

The suite is also invoked from **`tools/verify-os-health.ps1`** (step `contract-tests`) and **`tools/os-validate-all.ps1`** (validation `contract-tests`) after JSON manifest/schema checks.

## What is checked

| Area | Rule |
|------|------|
| **script-manifest.json** | Every `tools/*.ps1` path exists on disk. |
| **os-manifest.json** | `entrypoints` that live under `tools/` exist. |
| **Manifest ↔ schema** | The same manifest/schema pairs as **`tools/verify-json-contracts.ps1`**, plus each `quality-gates/*.json` file and `schemas/quality-gate.schema.json`. |
| **Documentation** | In `README.md`, `INDEX.md`, `docs/*.md`, and `recipes/*.md`, any line that starts a `pwsh` / `powershell` command referencing `tools/...ps1` points at a real file. |
| **os-capabilities.json** | Each `skill` matches a directory under **`source/skills/`**. Any `entrypoint` or `validations` line that mentions `pwsh`/`powershell` and a `tools/...ps1` path resolves to a file. |
| **capability-manifest.json** | `relevantSkills` and `relevantPlaybooks` exist; each `validators` line that names `tools/...ps1` resolves to a file. |
| **quality-gates** | Each `requiredValidators[].script` exists. |
| **agent-adapters-manifest.json** | Each `generatedTargets[].source` path exists (canonical source for generated adapter trees). |
| **Release gate evidence** | Each line in **`quality-gates/release.json`** `requiredEvidence` either matches a keyword tied to a **`requiredValidators`** id (see **`tests/contracts/release-evidence-keywords.json`**) or is listed under **`humanOnlyEvidenceSubstrings`** for non-automated process text. |
| **Strict profile maturity** | Every `tools/...ps1` referenced from **`tools/os-validate.ps1`** must appear in **`script-manifest.json`** with `maturity` not `experimental` or `deprecated`, unless the tool id is allowlisted in **`tests/contracts/strict-profile-allowlist.json`**. Missing `maturity` is treated as **stable**. |
| **Deprecation surfaces** | **`tools/verify-deprecations.ps1 -Strict`** must pass (orchestrator/gate surfaces free of forbidden deprecated references). |
| **JSON contracts** | **`tools/verify-json-contracts.ps1`** must pass (delegated). |

## Data files under `tests/contracts/`

See **`tests/contracts/README.md`** for **`strict-profile-allowlist.json`** and **`release-evidence-keywords.json`**.

When you change **`quality-gates/release.json`** evidence wording, update **`release-evidence-keywords.json`** (or extend **`humanOnlyEvidenceSubstrings`** for purely human checklist lines).

When a strict-path tool must stay experimental or deprecated temporarily, add its **`script-manifest.json`** `id` to the appropriate array in **`strict-profile-allowlist.json`** and document the exception in your change log or PR.
