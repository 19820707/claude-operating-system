# Commit Boundaries Policy

## Principle

Each commit must be **atomic**, **focused**, and **independently reviewable**. A commit that mixes concerns is a commit that cannot be safely reverted, cherry-picked, or audited.

---

## Prohibited combinations in a single commit

| Mix | Risk |
|-----|------|
| Logic change + documentation | Logic reverts pull docs; doc reverts expose logic |
| Config change + code change | Config error causes code blame confusion |
| Refactor + feature | Cannot bisect regressions |
| Test + implementation (cross-concern) | Obscures whether tests actually drove implementation |
| Multiple independent bug fixes | Cannot isolate which fix introduced regression |
| Schema migration + application code | Cannot stage migration independently |
| Secrets removal + functional change | Audit trail polluted |
| Formatting/whitespace + semantic change | Diff noise hides real change |

---

## Required commit structure

```
<type>(<scope>): <imperative summary under 72 chars>

[optional body: what changed and why, not how]
[optional: breaking change footer, issue reference]
```

**Types:** `feat` `fix` `docs` `refactor` `test` `chore` `ci` `perf` `security`

---

## File scope limits

| Scenario | Max files |
|----------|-----------|
| Single feature | ≤ 20 files |
| Bug fix | ≤ 10 files |
| Refactor | ≤ 30 files |
| Documentation | ≤ 15 files |
| Emergency hotfix | ≤ 5 files |

Exceeding these limits requires documented justification in the commit body.

---

## Invariants

- **No binary diff** without explicit annotation in commit body.
- **No force-push** to shared branches. Rewrite history only in isolation branches.
- **No `WIP` or placeholder messages** — every commit must describe what it does.
- **fix-of-fix chains** (fixing a fix committed < 48h ago) are a code smell — trigger review before proceeding.

---

## Verification

`pwsh tools/verify-commit-boundaries.ps1` — checks staged diff for scope violations and message format.
Runs automatically via `tools/change-velocity-gate.ps1` (fix-of-fix signal).
