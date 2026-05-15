# Critical Surface: pii

**Model:** Opus mandatory
**Mode:** Critical — explicit approval required before any change
**Fail posture:** fail-closed — when in doubt, do not expose or log

---

## What counts as this surface

- user personal data (name, email, phone, address, DOB)
- authentication credentials (passwords, tokens, API keys)
- payment data (card numbers, bank accounts)
- government IDs (SSN, passport, NIF, NHN)
- health or sensitive personal information
- device identifiers linked to a person
- any data that identifies or can identify an individual

---

## Pre-implementation checklist

- [ ] Data minimization: is this PII field strictly necessary?
- [ ] Storage location confirmed: encrypted at rest?
- [ ] Transmission confirmed: encrypted in transit (TLS)?
- [ ] Retention policy defined: when is it deleted?
- [ ] Access control: who can read this field?
- [ ] Log safety: is this field excluded from all logs?
- [ ] Redaction function in place for audit trails

---

## Implementation rules

- Never log raw PII — always redact (hash, truncate, or omit)
- Use a canonical redaction function: `SHA-256(value).slice(0,16)` for IDs
- Never return PII in error messages or stack traces
- Never store PII in URLs, query strings, or localStorage
- PII fields in DB must be encrypted at rest or access-controlled
- API responses must not include PII fields not explicitly requested
- Test data must never use real PII — use synthetic data only

---

## Redaction pattern (reference)

```typescript
// Safe for audit logs — not reversible, consistent for correlation
function redactForLog(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex").slice(0, 16);
}
```

---

## Validation checklist

- [ ] No PII in log output (check test assertions)
- [ ] No PII in error responses (check error handler)
- [ ] No PII in URLs (check route definitions)
- [ ] Redaction function used consistently — not imported from module with DB transitive dep (H3/H4)
- [ ] Synthetic data used in all tests

---

## Rollback

```bash
# Code rollback
git revert <commit> --no-edit

# Data exposure rollback: depends on scope
# If PII was logged: rotate/purge affected log streams (manual, human decision)
# If PII was exposed via API: assess scope, notify if required by regulation
```

---

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| Logging raw userId, email, phone | PII leak in log infrastructure |
| PII in error messages | Exposed in monitoring/alerting tools |
| Real user data in tests | GDPR/compliance violation |
| PII in URL query params | Logged by proxies, CDNs, browsers |
| Shared redaction utility with DB transitive dep | H3 — breaks in test/middleware |
