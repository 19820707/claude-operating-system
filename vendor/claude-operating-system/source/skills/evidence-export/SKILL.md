---
name: evidence-export
description: "Use when producing a sanitized audit bundle via export-audit-evidence for release or compliance handoff."
category: verification
version: 1.0.0
user-invocable: true
---

# Evidence export

## Purpose

Run `export-audit-evidence.ps1` per `docs/AUDIT-EVIDENCE.md` and manifest schema: redacted paths, no secrets, bounded size.

## Non-goals

- Shipping raw `logs/` or `.env` contents.

## Inputs

- Export manifest parameters; destination directory policy.

## Outputs

- Tarball or folder per tool contract; checksum note for recipients.

## Operating mode

- Default risk level: high.
- Allowed modes: dry-run/read manifest first; write to agreed export root.
- Human approval required for: off-machine transfer of bundles containing repo-identifying metadata.
- Safe for autonomous execution: no for final publish; yes for local dry-run.

## Procedure

1. Read `docs/AUDIT-EVIDENCE.md` invariants.
2. Invoke export tool with explicit output path; inspect manifest JSON inside bundle.
3. Attach evidence pointers to release record or ticket.

## Validation

- Recipient checklist: no PEM blocks, no `.env`, paths redacted per doc.

## Failure modes

- Oversized bundle; accidental inclusion of gitignored secrets tree.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Pre-release: export with default redaction profile; store in `local-evidence/` only if gitignored.

## Related files

- `tools/export-audit-evidence.ps1`, `docs/AUDIT-EVIDENCE.md`, `schemas/audit-evidence-manifest.schema.json`, `playbooks/release.md`
