<!-- Generated from source/skills/session-memory-auditor/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/session-memory-auditor/SKILL.md. -->
---
name: session-memory-auditor
description: "Use when validating session-memory manifest, scripts, and learning/decision artifacts for drift or policy."
category: verification
version: 1.0.0
user-invocable: true
---

# Session memory auditor

## Purpose

Apply `session-memory-manifest.json`, `verify-session-memory.ps1`, and session scripts (`session-prime`, `session-absorb`, `session-digest`) contracts without inventing state.

## Non-goals

- Reading full `learning-log.md` in large sessions without query-docs-index first.

## Inputs

- Project `.claude` tree or OS repo; manifest paths.

## Outputs

- Verify envelope; list of missing files or schema drift.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only audit; writes only via approved session scripts.
- Human approval required for: editing decision-log format on production mirrors.
- Safe for autonomous execution: yes for verify; absorb/digest need human context.

## Procedure

1. OS repo: `pwsh ./tools/verify-session-memory.ps1`.
2. App repo: confirm copied scripts match OS versions after `os-update-project`.
3. Cross-check `os-manifest.json` `sessionMemory` path.

## Validation

- `verify-session-memory` and health session-memory step pass.

## Failure modes

- Stale `.claude` session files not listed in manifest. JSONL parse errors in decision log handling.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- After manifest bump: run verify + `os-validate-all` session-memory cycle if touching scripts.

## Related files

- `session-memory-manifest.json`, `tools/verify-session-memory.ps1`, `tools/session-prime.ps1`, `workflow-manifest.json`
