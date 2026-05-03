# OS workspace context (local)

**Purpose:** Non-versioned notes for *this* `claude-operating-system` checkout. Helps operators remember local defaults, last validation runs, and audit notes.

**Warning:** Do **not** store secrets, tokens, API keys, customer data, or full environment dumps. Treat this file like a scratchpad with the same hygiene as `session-state.md`.

---

## Local environment (fill in)

| Field | Value |
|-------|-------|
| Date captured | |
| OS | |
| Shell | |
| PowerShell | |
| Bash on PATH | yes / no |
| Git checkout | yes / no |
| CI equivalent | e.g. GitHub Actions / local only |

---

## Runtime defaults

| Setting | Value |
|---------|-------|
| Preferred validation profile | quick / standard / strict |
| Local Bash syntax (`bash -n`) | enabled / skipped (Windows typical) |
| Human approval required for | Critical, Production, Incident, Migration, Release, Destructive (per `CLAUDE.md` / `policies/production-safety.md`) |

---

## Validation notes

| Date (UTC) | Command | Status | Notes |
|------------|---------|--------|-------|
| | | | |

Statuses must follow the OS taxonomy: **ok**, **warn**, **fail**, **skip**, **blocked**, **degraded**, **unknown**. **Never** treat `skip` or `warn` as `passed`.

---

## Runtime learnings

- 

---

## Audit notes

- 

---

## Local changelog

- 
