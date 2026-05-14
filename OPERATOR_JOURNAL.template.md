# Operator journal (local)

**Purpose:** A **local-only**, human-readable log for this checkout: failed validations, audit notes, decisions, environment quirks, and follow-ups. It is **not** a substitute for the decision log in bootstrapped projects (`.claude/decision-log.jsonl`); it is for **operators** working on the Claude OS repo itself.

**Hygiene:** Do **not** record secrets, tokens, API keys, passwords, private URLs with credentials, customer or employee PII, full `.env` contents, or raw tool output that may contain any of the above. Prefer status lines, validator names, ticket ids, and redacted paths.

---

## How to use

1. After `pwsh ./tools/init-os-runtime.ps1`, edit **`OPERATOR_JOURNAL.md`** (created from this template if missing).
2. Append dated sections; keep entries short enough to skim in a minute.
3. Never commit this file — it is **gitignored**.

---

## Template sections (copy as needed)

### Validation / CI

| Date (UTC) | Command / gate | Result | Notes (no secrets) |
|------------|------------------|--------|----------------------|
| | | ok / warn / fail / skip | |

### Audits / reviews

| Date (UTC) | Scope | Outcome | Follow-up |
|------------|-------|---------|-----------|
| | | | |

### Decisions (local)

| Date (UTC) | Decision | Rationale | Owner |
|------------|----------|-----------|-------|
| | | | |

### Environment notes

| Topic | Note |
|-------|------|
| OS / shell | |
| Paths / drives | |
| Network / proxy (no credentials) | |

---

## Quick checklist before saving

- [ ] No secrets or credentials
- [ ] No full stack traces pasted verbatim (summarize + pointer to log file if needed)
- [ ] Status vocabulary matches `docs/VALIDATION.md` (ok / warn / fail / skip / …)
