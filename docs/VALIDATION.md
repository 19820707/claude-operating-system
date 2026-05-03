# Validation profiles and contracts

## Profiles (`tools/os-validate.ps1`)

| Profile | Scope (summary) |
|---------|-------------------|
| **quick** | JSON contracts (including budgets and script manifest), runtime budget, context economy, **`verify-compatibility`** (platform matrix vs `script-manifest.json`), **`verify-lifecycle`** (install/init/update manifest vs repo paths), **`verify-distribution`** (packaging manifest vs repo), doc-contract verifier, **skills** (manifest, structure, `verify-skills.ps1`), **playbooks** (`verify-playbooks.ps1`; add `-Strict` on **strict** profile), **recipes** (`verify-recipes.ps1`; add `-Strict` on **strict** profile), PowerShell syntax (via underlying tools), bootstrap manifest. No full `verify-os-health` aggregate. |
| **standard** | quick + Git hygiene (warn if not a Git checkout), **`verify-no-secrets`** (warn-tier ambiguous patterns), **`verify-upgrade-notes`** (warn when **`schemaVersion`** on disk exceeds documented max), docs index, session memory, agent adapters, workflow/capabilities/runtime-profiles manifests, adapter drift (warn unless strict), `os-doctor`. |
| **strict** | standard + **`-Strict`** on skills manifest, structure, drift, **playbooks**, **`verify-no-secrets`**, and **`verify-upgrade-notes`** (undocumented contract bumps **fail**); `tools/os-validate-all.ps1 -Strict` (bootstrap smoke, session cycle, release dispatcher, bash `-n` when Bash is required on PATH). Adapter drift can **fail** release (`-FailOnDrift`). |

Orchestration entrypoints:

- `pwsh ./tools/os-validate.ps1 -Profile <name> [-Json] [-SkipBashSyntax] [-WriteHistory]` — exits **1** when aggregate `status` is **warn** or **fail**, or when any child verifier emitted a non-**ok** envelope status such as **skip**, **blocked**, **degraded**, **unknown**, or **not_run** (exit code **0** only when aggregate status is **ok**).
- `pwsh ./tools/os-runtime.ps1 validate -Profile <name>` (or `-ValidationProfile`; same behavior when the profile name is `quick`, `standard`, or `strict`).

Full release aggregate (unchanged):

- `pwsh ./tools/os-validate-all.ps1 -Strict [-RequireBash] [-Json] [-WriteHistory]`

## Status taxonomy

| Status | Meaning |
|--------|---------|
| **ok** | Check succeeded; no blocking issue. |
| **warn** | Non-blocking finding — **not** equivalent to passed for release interpretation. |
| **fail** | Blocking; exit code non-zero when appropriate. |
| **skip** | Not run (e.g. Bash absent with local policy) — **not** passed. |
| **blocked** / **degraded** / **unknown** | Treat as non-green until investigated. |
| **not_run** | Step or gate not executed — **not** passed (explicit in envelopes and strict aggregation). |

Canonical vocabulary and cross-checks: **`gate-status-contract.json`** + **`schemas/gate-result.schema.json`**; run **`pwsh ./tools/verify-gate-results.ps1`** (also invoked from **`pwsh ./tools/os-validate.ps1`**) to ensure `runtime-budget.json`, **`quality-gates/release.json`** `passInterpretation`, and **`schemas/os-validator-envelope.schema.json`** stay aligned — reduces “looks green” drift across scripts and docs.

**Structural graph:** **`pwsh ./tools/verify-manifest-graph.ps1`** (quick+ profiles) walks manifest↔schema pairs, script paths, skills/playbooks/recipes, capability references, distribution includes, and release-gate tool maturity vs `component-manifest.json` allowlist.

**Generated targets:** **`pwsh ./tools/verify-generated-drift.ps1`** (standard+; `-Strict` on strict profile) extends skills drift with generation-header checks; **`pwsh ./tools/sync-generated-targets.ps1`** regenerates copies. Schema fragment: **`schemas/generated-target.schema.json`** (adapter `generatedTargets` shape).

Configured explicitly in `runtime-budget.json` → `neverTreatAsPassed`. Normative wording: **`policies/invariants.md`** (I-001), **`docs/DEGRADED-MODES.md`**. Manifest-governed gates and the **release** / **strict** false-green contracts live under **`quality-gates/`**; see **`docs/QUALITY-GATES.md`** and **`pwsh ./tools/verify-quality-gates.ps1`**.

## JSON envelope (verifiers)

With `-Json`, new verifiers emit a shared shape (see `tools/lib/validation-envelope.ps1`). The JSON Schema is `schemas/os-validator-envelope.schema.json`; worked examples live under `examples/validation/` and are checked by `pwsh ./tools/verify-examples.ps1`.

```json
{
  "tool": "verify-runtime-budget",
  "status": "ok",
  "durationMs": 0,
  "checks": [],
  "warnings": [],
  "failures": [],
  "findings": [],
  "actions": []
}
```

`verify-os-health` uses a related aggregate JSON (`name`, `status`, `checks`, per-check `latencyMs`, `failures` / `warnings` **counts**, `totalMs`, `repo`). Schema: `schemas/os-health-envelope.schema.json`. See `docs/EXAMPLES.md`. For a sanitized audit tarball (manifest + bundle), see `docs/AUDIT-EVIDENCE.md` and `tools/export-audit-evidence.ps1`. Operational fixes for common failures are in **`docs/TROUBLESHOOTING.md`**; `verify-os-health` / `os-doctor` JSON include **reason**, **impact**, **remediation**, **strictImpact**, and **docsLink** on warn, fail, and skip rows where applicable.

## False green

**False green** means reporting success when some checks were skipped, warned, or unknown. Claude OS avoids counting **skip** or **warn** as **ok** for strict release gates. CI Ubuntu requires Bash for strict validation so shell syntax is not silently waived.

Operational framing (Portuguese, full taxonomy and local vs strict): [`docs/CAPACIDADES-OPERACIONAIS.md`](CAPACIDADES-OPERACIONAIS.md) — §10.

## Validation history (opt-in)

Append-only JSONL: `logs/validation-history.jsonl` (directory gitignored). Pass `-WriteHistory` to `init-os-runtime`, `verify-os-health`, `os-validate`, or `os-validate-all`. Records must not contain secrets or raw environment dumps.

## Before merge / release

1. `pwsh ./tools/os-validate-all.ps1 -Strict` (add `-RequireBash` when Bash is available).
2. Or `pwsh ./tools/os-validate.ps1 -Profile strict -Json` for profiled strict path.
3. Confirm aggregate status is **ok**, not **warn**, for release-critical repos.
4. No adapter drift, manifest/schema failures, or doc-contract failures.
