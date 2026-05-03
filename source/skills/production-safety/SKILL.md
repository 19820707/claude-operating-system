---
name: production-safety
description: "Use when a task touches production, auth, billing, PII, migrations, deployment, permissions, secrets, or rollback posture."
category: safety
version: 1.1.0
user-invocable: true
---

# Production Safety

Use this skill for any high-risk operational change. It converts safety policy into an execution checklist for Claude OS work.

## Operating contract

- Assume risk is high for auth, payments, PII, migrations, deployments, secrets, permissions, CI/CD, filesystem mutation, and network exposure.
- Require explicit human approval before destructive or irreversible action.
- Always define rollback before execution.
- Prefer read-only inspection before mutation.
- Do not expose PII, secrets, tokens, stack traces, or raw internal JSON in user-facing output.
- Never turn degraded, skipped, partial, or fallback behavior into success language.

## No-false-green contract

Report status precisely:

- `pass` means the required check actually ran and passed.
- `warn` remains warning, not success.
- `skip` remains skipped, not pass.
- fallback/demo/local behavior is degraded unless explicitly intended.
- partial validation is partial, not validated.
- unknown evidence is unknown, not assumed OK.

Invariant: **fallback != healthy; skipped != passed; warning != success**.

## Required checks

1. Identify the critical surface.
2. Identify blast radius and rollback path.
3. Confirm whether human approval is required.
4. Separate pass / warn / fail / skip / blocked outcomes.
5. Add or update regression coverage when behavior changes.
6. Report residual risk explicitly.

## Invariants

- Production mutation never happens without approval.
- Rollback must be known before deployment or destructive change.
- Sensitive output is summarized, not dumped.
- Safety gates take precedence over speed.
- Degraded runtime state must be visible to humans.

## Safety rules

- Do not expose secrets, tokens, PII, or raw stack traces in user-facing output.
- Do not treat `skip`, `warn`, `unknown`, `degraded`, `blocked`, or partial outcomes as passed or success.
- Do not perform destructive or irreversible production changes without explicit human approval and a defined rollback.
- Do not overwrite user-local state unless the operation is explicitly scoped and approved.

## Non-goals

- Duplicating full policy corpora; defer to `policies/*.md` and `CLAUDE.md`.

## Inputs

- Risk class, blast radius, approval state, and affected systems.

## Outputs

- Explicit approvals, rollback plans, and pass/warn/fail/skip reporting.

## Failure modes

- False-green language, missing rollback, or unapproved destructive change.

## Examples

- Inline procedures above illustrate intended use.

## Related files

- `skills-manifest.json`, `policies/production-safety.md` (repo root)
