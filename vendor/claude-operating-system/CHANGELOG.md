# CHANGELOG

## 1.0.0 — Claude OS Runtime v1

### Added

- Local workspace context template (`OS_WORKSPACE_CONTEXT.template.md`), idempotent `tools/init-os-runtime.ps1`, and opt-in JSONL validation history (`tools/write-validation-history.ps1`, `-WriteHistory` on health / validate flows).
- Runtime and context budgets (`runtime-budget.json`, `context-budget.json`) with verifiers and JSON schemas; script maturity manifest (`script-manifest.json`, `tools/verify-script-manifest.ps1`).
- Profiled orchestrator `tools/os-validate.ps1` (quick / standard / strict) and doc/contract verifier `tools/verify-doc-contract-consistency.ps1`; `os-runtime.ps1` commands `init` and profiled `validate`.
- Operator docs: `docs/QUICKSTART.md`, `docs/VALIDATION.md`, `docs/RELEASE-READINESS.md`.
- `agent-adapters-manifest.json` optional `canonicalSources`, `generatedTargets`, and `driftPolicy`; `verify-agent-adapter-drift.ps1` scans `templates/adapters` plus any **existing** generated paths when Git is available.
- `script-manifest.json` gains `shellScripts[]` for every `templates/scripts/*.sh`; `verify-script-manifest.ps1` enforces coverage and rejects **deprecated** tools with `defaultEnabled: true`.
- Unified runtime dispatcher: `tools/os-runtime.ps1`.
- Master manifest: `os-manifest.json`.
- Strict release validation: `tools/os-validate-all.ps1 -Strict`.
- Managed project updater: `tools/os-update-project.ps1`.
- Shared safe-output helpers: `tools/lib/safe-output.ps1`.
- JSON schemas for core manifests under `schemas/`.
- Section-first docs index and query tool.
- Declarative capability registry and router.
- Progressive workflow manifest and status tool.
- Security and release checklists installed into project scaffolds.
- Cross-platform CI validation on Ubuntu and Windows.

### Changed (governance + docs)

- Documented graphify-aligned **session pipeline** (prime → export) in `ARCHITECTURE.md` / `README.md` / `INDEX.md`.
- Optional **Confiança** column on `session-state` decisions; `session-index.sh` indexes it; `salience-score.sh --digest` surfaces `session_decision_low_confidence`.
- Canonical `confidence` enum on `decision-log.schema.json`; validation in `decision-append.sh`; `decision-audit.sh` maps CLI HIGH|MEDIUM|LOW → KNOWN|INFERRED|AMBIGUOUS; `policy-compliance.sh` treats weak tokens like legacy LOW for evidence checks.
- `verify-json-contracts.ps1` validates `templates/local/decision-log.schema.json`, `runtime-budget.json`, `context-budget.json`, and `script-manifest.json` against their schemas.
- `verify-runtime-budget.ps1` enforces `maxFilesScanned` ordering and `approvalRequiredFor` labels; `verify-doc-contract-consistency.ps1` checks `os-manifest.manifests` paths, JSON/schema file pairs, `docs/RELEASE-READINESS.md` wording, and README **Get started** references `os-runtime.ps1`; `verify-context-economy.ps1` warns on repeated long paragraphs in `CLAUDE.md`.

### Runtime contract

Claude OS Runtime v1 is local-first, deterministic, manifest-governed, and human-gated for critical surfaces.

### Release gate

Run before release or merge:

```powershell
pwsh ./tools/os-runtime.ps1 validate -Strict
```

For changes touching runtime, bootstrap, CI, security, permissions, filesystem, or production-safety behavior: **human approval required**.
