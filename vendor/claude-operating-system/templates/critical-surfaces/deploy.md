# Critical Surface: deploy

**Model:** Opus mandatory
**Mode:** Production — human gate required
**Fail posture:** fail-closed — if readiness is not confirmed, do not deploy

---

## What counts as this surface

- production deployments (web, API, mobile, infra)
- CI/CD pipeline changes
- environment variable or secret rotation
- infrastructure mutations (scaling, networking, database)
- feature flag activation in production
- mobile app store submissions

---

## Pre-deployment checklist

- [ ] `release-readiness` assessment completed — verdict: GO
- [ ] All checks passing: typecheck, tests, lint
- [ ] No known blockers unresolved
- [ ] Rollback procedure defined and tested
- [ ] Monitoring and alerts confirmed active
- [ ] Runbook available for this deployment type
- [ ] Human approval obtained explicitly

---

## Implementation rules

- Never deploy autonomously — always human gate
- Never deploy with failing tests
- Never deploy without a defined rollback path
- Feature flags preferred over big-bang releases
- Deploy to staging before production when available
- Confirm health checks pass after deploy before closing

---

## Post-deploy validation checklist

- [ ] Health/readiness endpoints respond correctly
- [ ] Smoke tests pass in production
- [ ] No error rate spike in monitoring
- [ ] Key user flows functional
- [ ] Rollback ready and tested if needed

---

## Rollback

```bash
# Web/API: redeploy previous version
# Platform-specific — document exact command before deploying:
# Example: git revert <commit> + push to trigger CD pipeline
# Example: platform rollback command (Vercel, Railway, Heroku, etc.)

# Mobile: cannot rollback — submit hotfix build
# Always document the rollback procedure BEFORE deploying
```

---

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| Deploy without human approval | Autonomous production change |
| Deploy with failing tests | Known broken state in production |
| No rollback procedure defined | Stuck if deploy fails |
| Deploying infra and app simultaneously | Hard to isolate failure |
| No post-deploy validation | Silent failures go undetected |
