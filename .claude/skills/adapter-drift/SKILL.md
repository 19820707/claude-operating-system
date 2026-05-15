<!-- Generated from source/skills/adapter-drift/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/adapter-drift/SKILL.md. -->
---
name: adapter-drift
description: "Use when reconciling canonical sources with generated Claude, Cursor, or Codex adapter copies."
category: verification
version: 1.0.0
user-invocable: true
---

# Adapter Drift

## Purpose

Detect and repair drift between canonical repository sources and generated multi-agent adapter copies (for example `.claude/`, `.cursor/`, `.codex/` paths declared in manifests).

## Non-goals

- Editing canonical sources to match hand-edited generated files without review.

## Inputs

- `agent-adapters-manifest.json`, `skills-manifest.json`, and sync tools (`sync-agent-adapters.ps1`, `sync-skills.ps1`).

## Outputs

- Drift report, regenerated files where declared, and honest pass or fail status.

## Operating mode

- Default risk level: high.
- Allowed modes: read-only drift detection; write mode only via approved sync scripts.
- Human approval required for: Production, Critical, Incident, Migration, Release, Destructive.
- Safe for autonomous execution: yes for read-only drift checks; no for applying sync without confirmation when writes affect protected surfaces.

## Procedure

1. Run `tools/verify-agent-adapter-drift.ps1` and `tools/verify-skills-drift.ps1` (add `-Strict` in release gates).
2. If drift exists, identify whether canonical or generated should win; canonical wins unless an explicit, documented exception says otherwise.
3. Regenerate using `tools/sync-skills.ps1` and `tools/sync-agent-adapters.ps1` rather than manual multi-file edits.
4. Re-run drift validators until clean or document residual risk with owner.
5. Never write paths outside declared adapter targets.

## Validation

- Strict drift checks pass after regeneration.
- Manifest `generatedTargets` lists match files actually written.

## Failure modes

- Manual edits to generated copies reintroducing drift on the next sync.
- Sync tools overwriting paths not declared in manifests.

## Safety rules

- Do not expose secrets.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without approval.
- Do not overwrite undeclared user-local files or paths outside manifest `generatedTargets`.

## Examples

- See `examples/skills/adapter-drift.md`.

## Related files

- `skills-manifest.json`, `agent-adapters-manifest.json`, `policies/multi-tool-adapters.md` (repo root)
