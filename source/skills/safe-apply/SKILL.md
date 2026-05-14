---
name: safe-apply
description: "Use when invoking or authoring tools that declare writes[] and must offer -DryRun, -WhatIf, or SupportsShouldProcess."
category: safety
version: 1.0.0
user-invocable: true
---

# Safe apply

## Purpose

Enforce `script-manifest.json` write metadata, `tools/lib/safe-apply.ps1` signals, and `verify-script-manifest.ps1 -Strict` rules before mutating repos or CI hosts.

## Non-goals

- Bypassing maintainer review for `writeRisk: high` tools.

## Inputs

- Tool id; raw `tools/*.ps1` for ShouldProcess/DryRun; manifest `writes` array.

## Outputs

- Dry-run plan or confirmed apply; envelope with warnings if signals missing.

## Operating mode

- Default risk level: high.
- Allowed modes: dry-run first; apply only with human ack for high-risk.
- Human approval required for: first enable of new writers in strict release; production apply.
- Safe for autonomous execution: no for apply; yes for read-only verify.

## Procedure

1. Read `script-manifest` entry for `writes`, `writeRisk`, `safeToRunInCI`.
2. Forward `-WhatIf`/`-DryRun` per `Get-SafeApplyForwardArgs` pattern used by orchestrators.
3. Fix scripts until strict manifest passes.

## Validation

- `pwsh ./tools/verify-script-manifest.ps1 -Json -Strict` clean for the tool.

## Failure modes

- Declaring `writes` without ShouldProcess family (CI warn; strict fail for high risk).

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- New `append-*.ps1` writer: add `CmdletBinding(SupportsShouldProcess=$true)` and `ShouldProcess` before writes.

## Related files

- `script-manifest.json`, `schemas/script-manifest.schema.json`, `tools/lib/safe-apply.ps1`, `tools/verify-script-manifest.ps1`
