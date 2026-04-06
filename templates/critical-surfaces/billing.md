# Critical Surface: billing

**Model:** Opus mandatory
**Mode:** Critical — explicit approval required before any change
**Fail posture:** fail-closed — if in doubt, do not charge; never double-charge

---

## What counts as this surface

- payment processing flows (charge, refund, capture, void)
- subscription management (create, update, cancel, pause)
- pricing logic (plan selection, proration, discounts)
- payment provider integrations (Stripe, PayPal, etc.)
- webhook handlers for payment events
- entitlement gates tied to payment status
- invoice generation and billing records

---

## Pre-implementation checklist

- [ ] Idempotency key defined for every charge operation
- [ ] Double-charge scenario mapped and prevented
- [ ] Refund path defined
- [ ] Webhook signature verification in place
- [ ] Payment state machine documented (pending → success → failed → refunded)
- [ ] Test mode vs live mode separation confirmed
- [ ] Rollback defined: what happens if charge succeeds but downstream fails?

---

## Implementation rules

- Every charge operation must have an idempotency key
- Never charge based on client-supplied amount — always derive server-side
- Never store raw card data — use provider tokens only
- Webhook handlers must verify signature before processing
- Failed charge must not grant the entitlement
- Successful charge must be recorded before granting entitlement
- All billing events must be logged with structured audit trail

---

## Validation checklist

- [ ] Test mode used in all tests — never real charges in CI
- [ ] Idempotency: same request twice → same result, no double charge
- [ ] Failure paths tested: payment fails → entitlement not granted
- [ ] Webhook: invalid signature → rejected
- [ ] Audit log: charge event recorded with amount, provider ref, userId (redacted)

---

## Rollback

```bash
# Code rollback
git revert <commit> --no-edit

# Billing state rollback: depends on provider
# Stripe: issue refund via dashboard or API (manual confirmation required)
# Never autonomous refund without explicit approval
```

---

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| No idempotency key on charge | Double charge on retry |
| Client-supplied price | Price manipulation |
| Grant entitlement before recording charge | Charge succeeds, record fails → free access |
| No webhook signature verification | Spoofed payment events |
| Logging raw card data or full token | PCI violation |
