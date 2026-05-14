# /release-readiness

**Model:** Opus
**Mode:** Phase → Production

Perform a release readiness assessment:
1. repository state — branch, uncommitted changes, pending PRs
2. validation state — typecheck, tests, lint: all passing?
3. release blockers — what must be resolved before release?
4. rollback readiness — is rollback documented and executable?
5. operational readiness — runbooks, monitoring, alerts in place?
6. generate go/no-go report

**Output format:**
```
## Release Readiness Report
Date: <date>
Branch: <branch>
Commit: <hash>

### Checks
- [ ] typecheck: PASS/FAIL
- [ ] tests: PASS/FAIL (N failures)
- [ ] lint: PASS/FAIL

### Blockers
- <list or "none">

### Rollback
<exact command>

### Verdict
GO / NO-GO — <reason>
```

**Rules:**
- do not declare GO if any blocker is unresolved
- do not declare GO if rollback is undefined
- production deploy requires explicit human approval after GO verdict
