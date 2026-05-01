# ARCHITECTURE — Claude OS Runtime

Claude OS Runtime is a local-first engineering runtime for Claude-driven projects. It turns a repository into a governed agent workspace with manifests, skills, policies, workflow gates, validation, and bootstrap/update tooling.

## Core flow

```text
os-manifest.json
  -> subsystem manifests
  -> validators
  -> health / doctor / validate-all
  -> init-project / update-project
  -> project .claude runtime artifacts
```

## Layers

| Layer | Artefacts | Purpose |
|---|---|---|
| Runtime contract | `VERSION`, `os-manifest.json`, `CHANGELOG.md` | Versioned operational contract |
| Bootstrap contract | `bootstrap-manifest.json`, `init-project.ps1` | Deterministic project scaffold |
| Navigation | `docs-index.json`, `query-docs-index.ps1` | Section-first documentation retrieval |
| Capabilities | `os-capabilities.json`, `route-capability.ps1` | Cheap safe routing to skills/checks |
| Workflow | `workflow-manifest.json`, `workflow-status.ps1` | Progressive artifact-first delivery gates |
| Safety | `templates/checklists/*`, `policies/*` | Human-gated safety and release controls |
| Validation | `tools/verify-*.ps1`, `os-validate-all.ps1` | Drift detection and release validation |
| Runtime ops | `os-runtime.ps1`, `os-doctor.ps1`, `os-update-project.ps1` | Unified CLI, diagnostics, managed updates |

## Runtime entrypoint

```powershell
pwsh ./tools/os-runtime.ps1 help
pwsh ./tools/os-runtime.ps1 health
pwsh ./tools/os-runtime.ps1 validate -Strict
pwsh ./tools/os-runtime.ps1 route -Query "security review"
pwsh ./tools/os-runtime.ps1 docs -Query bootstrap
pwsh ./tools/os-runtime.ps1 workflow -Phase verify
```

## Project scaffold

`init-project.ps1` installs managed runtime artifacts into `.claude/`, including docs index, capability registry, workflow manifest, checklists, skills, commands, agents, policies, scripts, and local state seeds.

## Invariants

- Runtime manifests are source of truth.
- Critical scaffold paths are declared in `bootstrap-manifest.json`.
- User/project-owned state is not overwritten by `os-update-project.ps1`.
- Critical surfaces require human approval.
- User-facing output must not expose secrets, PII, stack traces, or raw generated reports.
