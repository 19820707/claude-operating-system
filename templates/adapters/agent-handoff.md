# Handoff protocol (prime → absorb → digest)

## Flow

1. **Prime** before deep work — load bounded context: **`session-prime`** (`pwsh .claude/scripts/session-prime.ps1`).
2. **Absorb** during work — append durable notes: **`session-absorb`** (`pwsh .claude/scripts/session-absorb.ps1`).
3. **Digest** before you stop — record outcome: **`session-digest`** (`pwsh .claude/scripts/session-digest.ps1`).

Canonical script bases: **session-prime**, **session-absorb**, **session-digest** (each has a matching `*.ps1` under `.claude/scripts/`).

## Rules

- **Never** rely on chat memory alone — update **`.claude/session-state.md`** when real project state changes (branch, risks, next steps).
- Record material decisions via digest and, where configured, **`.claude/decision-log.jsonl`** / learning log — follow project conventions.
- No secrets or tokens in logs.

## human approval required

Changing retention, PII handling, or audit policy for these logs requires **human approval required**.
