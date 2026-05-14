---
name: bootstrap-governance
description: "Use when initializing, validating, repairing, or auditing Claude OS project bootstrap, manifests, scripts, and critical paths."
category: governance
version: 1.0.0
user-invocable: true
---

# Bootstrap Governance

Use this skill when the work touches project scaffolding, `.claude/` initialization, `bootstrap-manifest.json`, install scripts, or CI drift detection.

## Operating contract

- Treat `bootstrap-manifest.json` as the source of truth for counts, bootstrap scripts, and critical paths.
- Prefer deterministic checks before filesystem writes.
- Keep bootstrap idempotent: re-running it must not destroy protected local state.
- Keep `-DryRun` side-effect free.
- Fail fast on unsafe paths, missing source files, duplicate manifest entries, or manifest/documentation drift.

## Required checks

1. Run `pwsh ./tools/verify-bootstrap-manifest.ps1`.
2. Run `pwsh ./tools/verify-doc-manifest.ps1` when documentation is touched.
3. Run `pwsh ./init-project.ps1 -ProjectPath <tmp> -DryRun -SkipGitInit` after bootstrap changes.
4. Run `bash -n install.sh` and `bash -n templates/scripts/*.sh` after shell changes.

## Invariants

- `bootstrap-manifest.json` owns bootstrap cardinality.
- Manifest paths are always relative and never contain `..`.
- Protected local files are never overwritten unless explicitly allowed by contract.
- Validation output must be short, actionable, and free of secrets or raw stack traces.
