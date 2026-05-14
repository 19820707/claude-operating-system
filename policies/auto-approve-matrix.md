# L7 — Auto-approve matrix (reduce micro-confirmations)

## Goal

Cut needless human prompts **without** weakening gates or **I-001** (`warn` / `skip` or `skipped` / `unknown` / `degraded` / `blocked` / `not_run` are **not** *passed*).

Align with `policies/autonomy-policy.json`, `docs/AUTONOMY.md`, `.agent/operating-contract.md` (L4), `policies/invariants.md`.

**Scope:** Claude OS improves work **upstream** of CI/CD; it does **not** replace **GitHub Actions**, **production controls**, or **human approval** at critical transitions (`README.md`, `ARCHITECTURE.md`).

---

## Three columns

| **Always autonomous** | **Autonomous if reversible and validated** | **Always gated** |
|-----------------------|---------------------------------------------|------------------|
| Read-only cognition and repo inspection on **any** surface. | Local mutations that are **scoped**, **reversible**, **diff-visible**, and **validated** (agreed profile; required checks **`ok`**), with explicit **rollback** path. | Mutations on steward surfaces; external blast radius; governance changes. |
| See explicit verb list below. | Includes governed sync of declared generated targets, doc/manifest edits after green profile. | See explicit gated list below. |

If a required check is non-`ok`, or rollback is unclear, **do not** treat the work as column 2 — **escalate** (column 3 or human).

---

## Explicit: always autonomous (no extra human ping)

| Category | Examples (non-exhaustive) |
|----------|---------------------------|
| **Verbs** | `read`, `list`, `search`, `inspect`, `analyze`, `report` (and equivalents: view, cat, show metadata, dry inventory) on **any** surface — including auth, RLS, migration **files**, billing, CI, production-adjacent paths — **as long as** read-only and **no secrets**. |
| **Git read** | `git status`, `git diff`, `git log` (no mutating git ops). |
| **Typecheck / test / lint** | Running **typecheck**, **tests**, and **linters** locally (or in CI read-only job) to gather signal is **autonomous**; **I-001** still applies — a non-`ok` result must **not** be summarized as pass for merge/release. |
| **Supabase / auth (read-only)** | List tables/columns from dashboard or CLI **read-only** role; read `auth` config or RLS policy **definitions** as text/API read-only; inspect JWT claims shape **without** holding service keys in repo. |

---

## Explicit: always gated (human / steward path)

Writes or effects in these classes stay **gated** per `requiresHumanApproval.surfaces` and this matrix — **not** column 1:

| Area | Examples |
|------|-----------|
| **Auth / identity** | Changing IdP rules, OAuth client secrets on server, privilege elevation. |
| **RLS / policies with runtime effect** | SQL or dashboard edits that **change** who can read/write rows in shared DBs. |
| **Migrations** | Applying DDL/DML to **shared** or **production** Supabase / Postgres; `supabase db push` to non-local targets. |
| **Secrets** | Creating/rotating keys, writing `.env` with real values, running commands that embed tokens. |
| **Deploy / release** | Publish artifacts, tag release, edge config rollout. |
| **Destructive** | `DROP`, mass delete, force-push. |
| **Policy relaxation** | Widening `neverTreatAsPassed`, skipping validators, weakening quality gates — **I-008**. |

**Supabase / auth (gated):** applying migration to linked project; disabling RLS “temporarily”; running `supabase gen` or service-role scripts that **mutate** data; storing **service_role** key in repo; linking prod DB from local without approval path.

---

## Column detail (reference tables)

### Always autonomous — examples

| Example | Notes |
|---------|--------|
| `git status` / `git diff` / `git log` | No apply / push. |
| Ripgrep / semantic search | Prefer bounded paths. |
| Read repo files as text | Includes sensitive paths; still read-only. |
| Read-only Supabase metadata | No DML/DDL; read-only role. |

### Autonomous if reversible and validated — examples

| Example | Minimum conditions |
|---------|-------------------|
| Docs / comments / schema-compatible JSON | `os-validate` (or agreed profile) **ok** for required checks; no gate relaxation. |
| `sync-skills` and declared generated targets | After sync: `verify-skills*`, drift clean where strict requires it. |
| **Local commit** | Only if repo policy allows; tests/typecheck/lint/no-secrets as required **pass** at **ok** semantics; **no** `git push`. |

### Always gated — examples

| Example | Why |
|---------|-----|
| `git push` / deploy / release | Remote / user trust. |
| SQL with effect on shared DB | Data plane risk. |
| Policy / `neverTreatAsPassed` / validator bypass edits | Governance. |

---

## Golden rule

- **Autonomous without human:** read-only verbs on **any** surface; `git status` / `git diff`; running **typecheck / test / lint** as **signal** (not as a trick to skip release gates).  
- **Gated:** writes to **auth / RLS / migrations / secrets / deploy / release / destructive / policy relaxation** — and anything in `requiresHumanApproval.surfaces`.
