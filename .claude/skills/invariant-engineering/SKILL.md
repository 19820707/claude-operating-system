---
name: invariant-engineering
description: "Use when defining, validating, evolving, or debugging invariants, semantic diffs, contract deltas, or verification gates."
category: verification
version: 1.0.0
user-invocable: true
---

# Invariant Engineering

Use this skill when correctness depends on a property that must remain true across edits, refactors, releases, or agent handoffs.

## Operating contract

- Prefer explicit invariants over implicit expectations.
- Keep invariants short, testable, and tied to real risk.
- Use semantic diff and contract-delta tools when API shape or behavior may change.
- Treat invariant bypasses as high-risk unless explicitly justified.
- Keep generated reports local and summarized in user-facing output.

## Required checks

1. Identify the invariant and the failure mode it prevents.
2. Map the invariant to a script, test, or manual evidence source.
3. Run `bash .claude/scripts/invariant-verify.sh` or the repo-local equivalent when applicable.
4. Run semantic diff checks for exported TypeScript contracts when touched.
5. Document stale, obsolete, or superseded invariants instead of silently deleting them.

## Invariants

- An invariant without verification evidence is only an assumption.
- Contract changes require explicit compatibility notes.
- Generated JSON reports are evidence, not UI output.
- Verification should fail closed when confidence is insufficient.
