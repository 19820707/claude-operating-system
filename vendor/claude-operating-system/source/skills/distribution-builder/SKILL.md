---
name: distribution-builder
description: "Use when building or verifying the portable OS zip via distribution-manifest and build-distribution / verify-distribution."
category: governance
version: 1.0.0
user-invocable: true
---

# Distribution builder

## Purpose

Operate `distribution-manifest.json`, `build-distribution.ps1` (`-WhatIf` first), and `verify-distribution.ps1` so `rootFiles`, `includeTrees`, and `mandatoryPackagedPaths` resolve.

## Non-goals

- Running build in CI when `safeToRunInCI` is false unless explicitly approved job.

## Inputs

- Manifest path lists; `dist/` output policy.

## Outputs

- Staging tree or zip; verify JSON envelope listing resolved path count.

## Operating mode

- Default risk level: high.
- Allowed modes: verify anytime; build with human approval off-main.
- Human approval required for: **Release**, **Destructive** (overwrite `dist/`), production promotion of artifact.
- Safe for autonomous execution: verify yes; build no without approval.

## Procedure

1. `pwsh ./tools/verify-distribution.ps1 -Json`.
2. `pwsh ./tools/build-distribution.ps1 -WhatIf` then real run if plan ok.
3. Attach verify output to release evidence.

## Validation

- Mandatory paths present inside zip/staging; exclude regexes not violated.

## Failure modes

- Missing new root file in `rootFiles`; pack-staging leak from bad regex.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Add `upgrade-manifest.json` to pack → extend `rootFiles` + verify-distribution.

## Related files

- `distribution-manifest.json`, `schemas/distribution-manifest.schema.json`, `tools/build-distribution.ps1`, `tools/verify-distribution.ps1`, `playbooks/release.md`, `docs/DISTRIBUTION.md`
