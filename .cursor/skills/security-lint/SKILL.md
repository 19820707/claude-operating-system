<!-- Generated from source/skills/security-lint/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/security-lint/SKILL.md. -->
---
name: security-lint
description: "Use when scanning for committed secrets, credential-shaped strings, or SECURITY-LINT policy before merge."
category: safety
version: 1.0.0
user-invocable: true
---

# Security lint

## Purpose

Run and interpret `verify-no-secrets` (warn vs strict), align with `docs/SECURITY-LINT.md`, and escalate ambiguous hits without leaking material in logs.

## Non-goals

- Full SAST or dependency CVE triage. Not a substitute for secret rotation or vault design.

## Inputs

- Repo root; optional `-Strict` policy; touched paths if doing scoped re-scan.

## Outputs

- Pass/fail/warn envelope; list of file:line classes (redacted); recommendation to fix or waive via human ticket.

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only scan; strict CI per policy.
- Human approval required for: waiving a fail as false positive in release branches.
- Safe for autonomous execution: yes for running the verifier; no for dismissing findings on protected branches.

## Procedure

1. `pwsh ./tools/verify-no-secrets.ps1 -Json` locally; add `-Strict` before release.
2. Cross-check `.gitignore` and tracked templates named in SECURITY-LINT.
3. On hit: rotate if real secret; replace with redacted example if doc-only.

## Validation

- Exit 0 only when policy-acceptable; strict gate must not treat warn as pass.

## Failure modes

- Pasting live keys into chat or tickets. Treating warn-only CI as clean for production.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Run strict once before tag; file ticket for each PEM-shaped block in non-secret fixtures.

## Related files

- `tools/verify-no-secrets.ps1`, `docs/SECURITY-LINT.md`, `playbooks/release.md` (preflight), `quality-gates/security.json`
