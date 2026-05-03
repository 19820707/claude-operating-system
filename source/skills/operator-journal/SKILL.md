---
name: operator-journal
description: "Use when recording local validation failures, audits, or decisions in OPERATOR_JOURNAL without committing secrets."
category: governance
version: 1.0.0
user-invocable: true
---

# Operator journal

## Purpose

Use gitignored `OPERATOR_JOURNAL.md` (see `docs/OPERATOR-JOURNAL.md`) for bounded, non-secret notes: what failed, commands run, next steps—never a substitute for decision-log JSONL where required.

## Non-goals

- Pasting credentials, tokens, or full env dumps into the journal.

## Inputs

- Local OS or project root; template `OPERATOR_JOURNAL.template.md` if present.

## Outputs

- Append-only markdown sections; optional pointers to tickets or commit SHAs.

## Operating mode

- Default risk level: low.
- Allowed modes: local write only; never tracked in git.
- Human approval required for: none (local artifact).
- Safe for autonomous execution: yes for redacted notes.

## Procedure

1. Confirm file is gitignored (see `.gitignore` patterns).
2. Log: date, command, exit status, redacted one-line failure, link id to external system.
3. Do not duplicate secret material from `verify-no-secrets` hits.

## Validation

- `git status` does not show journal file; no secret-shaped strings in new paragraphs.

## Failure modes

- Accidentally creating tracked `OPERATOR_JOURNAL.md` at repo root without ignore rule.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- After failed health: note step name + suggested `pwsh ./tools/...` remediation line only.

## Related files

- `docs/OPERATOR-JOURNAL.md`, `OPERATOR_JOURNAL.template.md`, `.gitignore`, `docs/RELEASE-READINESS.md`
