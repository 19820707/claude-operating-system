# Production Safety Policy

## Principle

No production-impacting action is fully autonomous. Production readiness means explicit evidence, bounded blast radius, known rollback, and no false green.

---

## No-false-green contract

Agents must never report a system as healthy when the result is partial, skipped, degraded, or using fallback behavior.

| State | Must be reported as |
|-------|---------------------|
| `pass` | success only when the required check actually ran and passed |
| `warn` | warning, not success |
| `skip` | skipped, not pass |
| fallback path | degraded / fallback, not healthy |
| partial validation | partial, not validated |
| local-only validation | local evidence only, not production-ready |
| unknown state | unknown, not assumed OK |

Required language:

- “passed” only for checks that executed and passed;
- “skipped” for checks intentionally not run;
- “not verified” for unavailable evidence;
- “degraded” when fallback/local/demo behavior was used;
- “blocked” when a critical contract failed.

Invariant: **fallback != healthy, skipped != passed, warning != success**.

---

## Allowed preparation

- release readiness analysis
- validation execution
- change review
- rollback drafting
- operational documentation
- deployment checklist generation
- non-destructive dry-runs

---

## Human gate required

- production deploy
- credential changes
- infra mutation
- live migration
- rollback on live environment
- risk acceptance
- auth/authz/security policy changes
- CI/release gate changes
- payment or billing changes

---

## Release evidence minimum

Before production-impacting work is described as ready:

1. Scope and blast radius are explicit.
2. Required checks are listed and their status is pass/warn/fail/skip.
3. Skips and warnings are explained.
4. Rollback path is known.
5. Human gate is identified.
6. Secrets/PII were not exposed.

---

## Reporting discipline

Do not dump raw logs. Report:

- check name;
- status;
- failure cause;
- relevant file/line when available;
- next safe action.

Production is never implicit. Human approval remains required even when all local validation passes.
