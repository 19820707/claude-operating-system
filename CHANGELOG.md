# CHANGELOG

## 1.0.0 — Claude OS Runtime v1

### Added

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
- `verify-json-contracts.ps1` validates `templates/local/decision-log.schema.json`.

### Runtime contract

Claude OS Runtime v1 is local-first, deterministic, manifest-governed, and human-gated for critical surfaces.

### Release gate

Run before release or merge:

```powershell
pwsh ./tools/os-runtime.ps1 validate -Strict
```

For changes touching runtime, bootstrap, CI, security, permissions, filesystem, or production-safety behavior: **human approval required**.
