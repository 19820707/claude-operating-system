# SECURITY-CHECKLIST

Use before any work touching auth, authorization, permissions, secrets, PII, payments, filesystem mutation, external network calls, CI/CD, deployment, or production data.

## Gate

**human approval required** before destructive, externally visible, production, auth, payment, PII, secret, or permission changes.

## Required evidence

- [ ] Critical surface identified.
- [ ] Blast radius described.
- [ ] Rollback path documented.
- [ ] Secrets and tokens are not logged, displayed, committed, or copied into prompts.
- [ ] PII is not exposed in logs, URLs, errors, screenshots, tests, or reports.
- [ ] Auth/authz behavior fails closed.
- [ ] Payment/webhook behavior is idempotent where applicable.
- [ ] External network calls are intentional and bounded.
- [ ] Filesystem writes are scoped to expected directories.
- [ ] Regression test or explicit manual verification is recorded.

## Output rule

Summarize findings. Do not paste stack traces, raw JSON reports, tokens, secrets, customer data, or local private paths into user-facing output.
