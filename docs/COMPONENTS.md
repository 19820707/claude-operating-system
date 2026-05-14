# Component maturity

The OS is partitioned into **components** — each has a **maturity** tier and owns an explicit set of **members** (tools, shell scripts, skills, playbooks, policies, JSON manifests, and quality-gate validators).

## Tiers

| Maturity | Meaning |
|----------|---------|
| **core** | Orchestration and primary contracts required for strict validation and release honesty. |
| **stable** | Supported delivery surfaces: validators, operators, mutations, secondary manifests, gates, policies. |
| **experimental** | Not allowed on **release** or **strict orchestrator** surfaces unless allowlisted (see below). |
| **internal** | Dot-sourced libraries; not primary CI entrypoints. |
| **deprecated** | Same restriction pattern as experimental for release / strict orchestrator paths. |

## Files

| File | Role |
|------|------|
| **`component-manifest.json`** | Source of truth: `components[]`, members, and `strictReleaseExperimentalAllowlist`. |
| **`schemas/component-manifest.schema.json`** | JSON Schema for the manifest. |
| **`tools/verify-components.ps1`** | Coverage (every script, skill, playbook, validator, manifest, policy maps to **exactly one** component) and surface checks. |
| **`os-manifest.json`** `manifests.components` | Pointer to `component-manifest.json`. |

## Verification

```powershell
pwsh ./tools/verify-components.ps1
pwsh ./tools/verify-components.ps1 -Json -Strict
```

- **Coverage**: no duplicate members across components; every entity from `script-manifest.json`, `skills-manifest.json`, `playbook-manifest.json`, `policies/*.md`, tracked manifests, and `quality-gates/*.json` validators must appear once.
- **Release gate** (`quality-gates/release.json` `requiredValidators`): any tool whose component is **experimental** or **deprecated** **fails** unless its **tool id** or **component id** is listed under **`strictReleaseExperimentalAllowlist`**.
- **Orchestrator** (`tools/os-validate.ps1` referenced tools): same rule when **`verify-components.ps1 -Strict`** is used (wired from **`os-validate.ps1 -Profile strict`** and **`verify-os-health.ps1 -Strict`**). Without `-Strict`, orchestrator issues are **warnings** only.

## Maintaining the manifest

When you add a **tool**, **skill**, **playbook**, **policy**, **manifest**, or **gate validator**, add a **member** to the appropriate component (usually **`stable-delivery`**). Regenerate or hand-edit **`component-manifest.json`** so coverage stays complete; **`verify-components`** will fail on the first missing member.

To temporarily allow an experimental component on release/strict surfaces, add its **`id`** or the **tool id** to **`strictReleaseExperimentalAllowlist`** and document the waiver in your change log or PR.
