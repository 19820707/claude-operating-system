# Critical Surface: auth

**Model:** Opus mandatory
**Mode:** Critical — explicit approval required before any change
**Fail posture:** fail-closed — deny by default, allow by explicit grant

---

## What counts as this surface

- authentication flows (login, token issuance, session management)
- authorization logic (permission checks, role evaluation, capability gates)
- entitlement engines (who can do what)
- middleware that enforces identity or access
- trust boundaries between services or actors
- session tokens, JWTs, API keys in code paths

---

## Pre-implementation checklist

- [ ] Current flow documented: who calls what, what is checked, what is returned
- [ ] Failure modes identified: what happens if the check fails, errors, times out
- [ ] Fail-closed confirmed: default is deny, not allow
- [ ] No silent fallback to a weaker check
- [ ] Change does not introduce allow-by-default for unknown inputs
- [ ] Rollback defined and executable

---

## Implementation rules

- Every new capability/permission must be explicitly added — no implicit grants
- Default branch of any switch/match on capability → deny
- Never trust caller-supplied identity without server-side verification
- Log all access denials with structured event (code, userRef redacted, requestId)
- Never log raw user IDs, tokens, or credentials — always redact
- Imports in auth middleware must not have transitive DB dependencies in test paths (see H3)

---

## Validation checklist

- [ ] Typecheck passes
- [ ] Unit tests cover: allow path, deny path, unknown input (→ deny), suspended/banned state
- [ ] No test uses real tokens or credentials
- [ ] Audit log emitted on deny (verify in test)
- [ ] Regression: existing authorized flows still pass

---

## Rollback

```bash
git revert <commit> --no-edit
# If middleware change: verify deny-by-default is restored
# If migration involved: see migrations.md surface
```

---

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| Allow-by-default for unknown capability | Privilege escalation |
| Silent catch on auth failure → proceed | Bypass |
| Two parallel checks for same boundary (H9) | Divergence → one path weakens |
| Logging raw userId or token | PII/credential leak |
| Importing DB module in auth middleware test | H3 — test breaks without DB |
