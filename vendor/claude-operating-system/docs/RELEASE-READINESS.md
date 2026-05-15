# Release readiness (human-gated)

There is **no** automated GitHub Release publish in this repository. Use the checks below as evidence before tagging or merging high-risk changes.

## Required commands

Run **one** of:

```powershell
pwsh ./tools/os-validate-all.ps1 -Strict -RequireBash -Json
```

```powershell
pwsh ./tools/os-validate.ps1 -Profile strict -Json
```

On Windows without Bash, local runs may use `-SkipBashSyntax` only where policy allows; **CI (Ubuntu) requires Bash** for strict validation (`bootstrap-validate` workflow).

## Required clean state

Interpret JSON / console output honestly. Do **not** treat as release-ready if any of the following are non-**ok** (or are **skip** / **warn** where policy forbids them):

- **Adapter drift** — no uncommitted changes under `templates/adapters` (and under any **existing** paths listed in `agent-adapters-manifest.json` → `generatedTargets`).
- **Manifest / schema** — `pwsh ./tools/verify-json-contracts.ps1` passes.
- **Doc contract** — `pwsh ./tools/verify-doc-contract-consistency.ps1` passes.
- **Script manifest** — every `tools/**/*.ps1` and every `templates/scripts/*.sh` is listed in `script-manifest.json` with accurate maturity metadata.
- **No false-green** — aggregate status **ok** only; **warn**, **skip**, **unknown**, **degraded**, **blocked**, and **not_run** are not release passes (see `runtime-budget.json` → `neverTreatAsPassed` and [VALIDATION.md](VALIDATION.md)).

## Evidence

Optionally append JSONL rows:

```powershell
pwsh ./tools/os-validate-all.ps1 -Strict -Json -WriteHistory
```

Output: `logs/validation-history.jsonl` (gitignored). Do not store secrets in history lines.
