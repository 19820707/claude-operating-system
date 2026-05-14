# Claude OS runtime output examples

This page points to **checked-in JSON** under `examples/` that mirrors the shapes produced by validators when you pass `-Json` (or the aggregate health envelope from `verify-os-health.ps1 -Json`).

## Schemas

| Artifact | Schema |
|----------|--------|
| Validator envelope (`New-OsValidatorEnvelope` — most `tools/verify-*.ps1` and `os-validate`) | `schemas/os-validator-envelope.schema.json` |
| Health aggregate (`New-OsHealthEnvelope` — `verify-os-health`) | `schemas/os-health-envelope.schema.json` (warn/fail/skip checks add **reason**, **impact**, **remediation**, **strictImpact**, **docsLink**) |
| Minimal `runtime-budget.json` (profiles + ordering) | `schemas/runtime-budget.schema.json` |
| Illustrative skills manifest (not canonical) | `schemas/skills-manifest.schema.json` |
| Illustrative playbook manifest | `schemas/playbook-manifest.schema.json` |
| Illustrative bootstrap manifest | `schemas/bootstrap-manifest.schema.json` |

## Validation envelopes (`examples/validation/`)

| File | Scenario |
|------|-----------|
| `os-validate-quick-ok.json` | `os-validate` **quick** profile: all steps **ok**, empty warnings/failures. |
| `os-validate-standard-warn.json` | **Standard** profile: doc-contract or adapter drift **warn**, aggregate `status` **warn**. |
| `os-validate-strict-fail.json` | **Strict** profile: `os-validate-all` step **fail**, aggregate **fail**. |
| `verify-agent-adapter-drift-warn.json` | Uncommitted edits under adapter paths; **findings** include `path` / `severity` / `detail`. |
| `verify-skills-manifest-fail.json` | Skills manifest checker **fail** (e.g. duplicate id) with **failures** and structured **findings**. |
| `verify-doc-contract-fail.json` | Doc/manifest coherence **fail** (e.g. bootstrap skill count mismatch) with contract **findings**. |
| `verify-runtime-budget-warn.json` | `verify-runtime-budget` **warn** (e.g. quick profile too strict for local-first Windows). |
| `verify-os-health-ok.json` | Aggregate health JSON: per-check `latencyMs`, numeric **warnings** / **failures** counts. |
| `runtime-budget-minimal-example.json` | Valid minimal `runtime-budget.json` (exercises schema **`$ref`** to `#/$defs/profile`). |

## Other examples

| Directory | File | Purpose |
|-----------|------|---------|
| `examples/skills/` | `skills-manifest-minimal-example.json` | One synthetic skill row showing required manifest fields. |
| `examples/playbooks/` | `playbook-manifest-minimal-example.json` | Single playbook row for manifest shape. |
| `examples/project-bootstrap/` | `bootstrap-manifest-minimal-example.json` | Minimal valid `bootstrap-manifest.json` (**project bootstrap success** contract). |

## Verifier

Run from repo root:

```bash
pwsh ./tools/verify-examples.ps1
```

This uses a **PowerShell-only** JSON Schema subset (types, `required`, `properties`, `items`, `enum`, numeric and string bounds, `uniqueItems`, `additionalProperties`, and `$ref` to `#/$defs/*` in the same schema file). It is **not** a full Draft 2020-12 engine; it is tailored to the schemas above. `os-validate-all` invokes this step after `verify-json-contracts`.

## Notes

- PowerShell’s `ConvertFrom-Json` represents JSON `[]` as `$null` in some cases; `verify-examples.ps1` normalizes that when validating **array** types.
- Canonical repo manifests (`skills-manifest.json`, `playbook-manifest.json`, `bootstrap-manifest.json`) live at the repo root; `examples/**` files are **documentation fixtures** unless stated otherwise.
