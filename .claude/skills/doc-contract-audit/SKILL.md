<!-- Generated from source/skills/doc-contract-audit/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/doc-contract-audit/SKILL.md. -->
---
name: doc-contract-audit
description: "Use when verifying that README, architecture docs, manifests, schemas, and validators describe the same commands and contracts."
category: verification
version: 1.0.0
user-invocable: true
---

# Doc Contract Audit

## Purpose

Ensure README, `ARCHITECTURE.md`, `CLAUDE.md`, manifests, JSON schemas, and validator scripts agree: documented commands exist, referenced scripts are present, and documentation avoids unsafe false-green language.

## Non-goals

- Rewriting product marketing copy unrelated to technical contracts.

## Inputs

- `os-manifest.json`, `script-manifest.json`, `docs-index.json`, and primary docs paths.

## Outputs

- Findings list with severities, suggested fixes, and validation envelope status.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only audit; edits only with normal code-review flow.
- Human approval required for: broad doc rewrites that imply behavioral promises.
- Safe for autonomous execution: yes for read-only checks; caution when proposing doc edits that assert CI behavior.

## Procedure

1. Run `tools/verify-doc-contract-consistency.ps1` and `tools/verify-doc-manifest.ps1`.
2. Cross-check README command examples against `tools/*.ps1` and `script-manifest.json`.
3. Search docs for unsafe phrasing such as equating `skip` or `warn` with passed.
4. Confirm manifest entrypoints and schema pairs reference existing files.
5. File targeted doc or manifest fixes; avoid silent divergence.

## Validation

- Doc contract tools exit zero with no failures; warnings triaged or owned.

## Failure modes

- Documented commands that were removed from the repo still appear as current.
- Manifest lists a validator path that does not exist.

## Safety rules

- Do not expose secrets.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without approval.
- Do not overwrite user-local generated copies except through declared sync flows.

## Examples

- See `examples/skills/doc-contract-audit.md`.

## Related files

- `skills-manifest.json`, `policies/multi-tool-adapters.md` (repo root)
