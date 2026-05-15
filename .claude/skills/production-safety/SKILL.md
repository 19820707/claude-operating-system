---
name: production-safety
description: "Use when a task touches production, auth, billing, PII, migrations, deployment, permissions, secrets, or rollback posture."
category: safety
version: 1.0.0
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

## Required checks

1. Identify the critical surface.
2. Identify blast radius and rollback path.
3. Confirm whether human approval is required.
4. Add or update regression coverage when behavior changes.
5. Report residual risk explicitly.

## Invariants

- Production mutation never happens without approval.
- Rollback must be known before deployment or destructive change.
- Sensitive output is summarized, not dumped.
- Safety gates take precedence over speed.
