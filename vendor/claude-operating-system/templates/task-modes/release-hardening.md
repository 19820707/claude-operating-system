---
name: release-hardening
description: Structured workflow for hardening a release candidate — validation, blockers, rollback readiness, go/no-go
type: task-mode
---

# Task Mode: release-hardening

**Model:** Opus — always
**Mode:** Phase → Production (human gate for the actual deploy)
**Approval:** Required before any production-impacting action. GO verdict does not authorise deploy.

---

## When to use

- Preparing a release branch for production
- Validating a feature branch before merge to main
- Pre-deploy hardening pass after a significant change set
- Release readiness assessment before a scheduled deployment

Not for: mid-development validation, local bugfix confirmation, individual feature testing.

---

## Sequence

### 1. Repository state

```bash
git status --short                    # uncommitted changes?
git log --oneline -5                  # recent commits
git diff main...HEAD                  # what is in this release vs main?
git stash list                        # any stashed work?
```

Blockers at this step:
- Uncommitted changes → must be committed or stashed (not ignored)
- Working tree dirty → resolve before proceeding

### 2. Validation suite

Run in this order — stop at first failure and investigate before continuing:

```bash
npm run typecheck                     # 0 type errors
npm run lint                          # 0 lint errors (or pre-existing only)
npm run test:unit                     # all pass
npm run test:integration              # all pass (if available)
npm run build                         # builds without error
```

For each failure, classify:
- **Pre-existing**: was this failing before this branch? (check main)
- **Introduced**: caused by changes in this branch → blocker

Pre-existing failures must be documented. Introduced failures are always blockers.

### 3. Surface scan

Check each critical surface touched by this release:

| Surface | Check |
|---------|-------|
| Auth / authz | Was this reviewed in Critical mode with Opus? |
| Migrations | Is down migration defined? Was staging run completed? |
| Billing | Idempotency verified? Webhook signature validated? |
| PII | No new fields logged? No PII in URLs? |
| Deploy | CI green? Rollback command defined? |

Any critical surface without the required approval → blocker.

### 4. Dependency review

```bash
# Check for new or upgraded dependencies in this release
git diff main...HEAD -- package.json package-lock.json

# For each new/upgraded dependency:
# - Is the version pinned?
# - Is the package known?
# - Does it introduce a known vulnerability? (npm audit)
```

```bash
npm audit --audit-level=high          # high or critical vulnerabilities?
```

### 5. Rollback readiness

Answer these before declaring GO:
- What is the previous stable commit? (`git log --oneline main`)
- What is the rollback command? (exact, executable)
- If schema changed: is the down migration available and tested?
- If config changed: is the previous config recoverable?
- Is the rollback runbook documented and accessible to the on-call engineer?

If rollback is not defined and executable → NO-GO.

### 6. Operational readiness

- Health / readiness endpoints exist and respond correctly?
- Monitoring and alerts active for this service?
- Runbook available for this release type?
- On-call engineer notified if this is a high-risk deploy?
- Deploy time window appropriate? (avoid Friday deploys, peak traffic)

### 7. Go / No-Go decision

Compile the report. Apply the decision rule:

**GO conditions** — all must be true:
- All validation checks pass (or pre-existing failures documented)
- No critical surface without required approval
- No high/critical npm audit findings (or documented accepted risk)
- Rollback command defined and executable
- Staging validation completed (for significant changes)

**NO-GO conditions** — any one is sufficient:
- Any introduced test failure
- Any critical surface change without approval
- Rollback not defined
- Working tree dirty at time of assessment
- Unresolved high/critical security vulnerability

---

## Output format

```markdown
## Release Readiness Report
Date: <date>
Branch: <branch>
Commit: <hash> — <message>
Assessed by: Claude (Opus) — requires human approval to deploy

### Validation
- [ ] typecheck: PASS / FAIL (<N> errors — pre-existing / introduced)
- [ ] lint: PASS / FAIL
- [ ] test:unit: PASS / FAIL (<N> failures — pre-existing / introduced)
- [ ] test:integration: PASS / FAIL / SKIPPED
- [ ] build: PASS / FAIL

### Critical surfaces
- [ ] Auth: not touched / approved in Critical mode
- [ ] Migrations: not touched / down migration defined / staging run done
- [ ] Billing: not touched / idempotency verified
- [ ] PII: not touched / no new log exposure
- [ ] Deploy: CI green / rollback defined

### Security
- [ ] npm audit: PASS / <N> high / <N> critical

### Blockers
- <list or "none">

### Rollback
```
git revert <hash> --no-edit && git push
```
<or exact rollback command for this release>

### Verdict
**GO** / **NO-GO** — <reason>

> GO verdict does not authorise deploy. Human approval required.
```

---

## Rules

- GO verdict does not authorise deploy — it is a recommendation
- Never declare GO with unresolved introduced failures
- Distinguish pre-existing failures from introduced failures — they have different urgency
- Rollback undefined → always NO-GO
- Staging run is required for: schema changes, auth changes, billing changes
- Friday deploys, peak traffic, and on-call gaps are operational risk — flag them

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| Skipping typecheck "because it was fine yesterday" | Type regression ships silently |
| Declaring GO with unreviewed critical surface | Security regression undetected |
| No rollback command defined | Cannot recover from bad deploy |
| Conflating pre-existing and introduced failures | Introduces false urgency or false confidence |
| Treating GO as deploy authorisation | Bypasses human gate |
| Hardening pass done on wrong branch | Assessment does not match what gets deployed |
