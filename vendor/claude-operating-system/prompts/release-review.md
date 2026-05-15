# Prompt: release-review

**Model:** Opus
**Mode:** Phase → Production (human gate for deploy)
**Output:** Structured go/no-go report

---

## Sequence

### 1. Repository state
```bash
git status --short        # uncommitted changes?
git log --oneline -5      # recent commits
git diff main...HEAD      # what's in this release vs main?
```

### 2. Validation state
```bash
npm run typecheck         # 0 errors?
npm run test:unit         # all pass?
npm run build             # builds cleanly?
```

### 3. Release blockers
- Any failing check → blocker
- Any uncommitted change → blocker (or intentional?)
- Any unresolved high/critical risk from architecture review → blocker
- Any migration without rollback defined → blocker
- Any auth/billing change without Critical-mode approval → blocker

### 4. Rollback readiness
- Is the previous stable version identifiable? (`git log`)
- Is the rollback command documented and executable?
- Is the down migration available (if schema changed)?

### 5. Operational readiness
- Health/readiness endpoints exist and respond?
- Monitoring and alerts active?
- Runbook available for this release type?

---

## Output format

```markdown
## Release Readiness Report
Date: <date>
Branch: <branch>
Commit: <hash> — <message>

### Checks
- [ ] typecheck: PASS / FAIL
- [ ] tests: PASS / FAIL (N failures — pre-existing / introduced)
- [ ] build: PASS / FAIL

### Blockers
- <list or "none">

### Rollback
<exact command>

### Verdict
GO / NO-GO — <reason>
```

---

## Rules

- GO verdict does not authorise deploy — human approval still required
- Never declare GO with unresolved blockers
- Distinguish pre-existing failures from introduced failures
- If rollback is not defined → NO-GO
