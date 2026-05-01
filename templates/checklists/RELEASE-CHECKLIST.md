# RELEASE-CHECKLIST

Use before merging, shipping, deploying, publishing, or handing off a completed change.

## Gate

**human approval required** before production deployment, destructive migration, public release, CI/CD mutation, permission expansion, or externally visible behavior change.

## Required evidence

- [ ] Scope and user-visible behavior summarized.
- [ ] Changed files reviewed.
- [ ] Acceptance criteria satisfied or gaps documented.
- [ ] Tests or manual validation recorded.
- [ ] Rollback path documented.
- [ ] Migration/data impact reviewed, if applicable.
- [ ] Security checklist completed for critical surfaces.
- [ ] Observability/logging impact reviewed.
- [ ] Known limitations documented.
- [ ] Follow-up work separated from release blockers.

## Output rule

Give a go/no-go recommendation with blockers, residual risk, and rollback notes. Do not include secrets, PII, raw stack traces, or raw generated reports.
