# Operating contract (all agents)

> **L4** abaixo fixa autonomia **read-only** em qualquer superfície. Matriz: `policies/auto-approve-matrix.md`. Invariantes: `policies/invariants.md` (I-001–I-010). Fronteiras por pasta: `docs/REPO-BOUNDARIES.md`. Autonomia máquina: `policies/autonomy-policy.json`, `docs/AUTONOMY.md`.

## Principles

- **local-first** — prefer repo manifests and scripts; no new mandatory external SaaS for core OS flows.
- **artifact-first** — commit deliberate artifacts; stage paths explicitly after review.
- **deterministic validation** — use repo checklists and `pwsh`/scripted gates where provided.
- **human-gated critical surfaces (mutations)** — auth, security, CI, release, filesystem, permissions, production, payments: **writes** and policy changes remain human-gated; **read-only** work on these surfaces is **not** micro-gated (see L4).
- **token-proportional execution** — read and validate only what the task requires.
- **fail-closed critical behavior** — never convert a critical failure into silent success.

## L4 — Operating contract: autonomous read-only (explicit)

**Truth:** Claude OS is a **governance filesystem** interpreted by agents and enforced by scripts; it is not an unsupervised daemon.

**Rule — autonomous without extra human micro-confirmation:**

The following are **autonomous on any surface**, including files or configurations related to **authentication**, **RLS**, **migrations**, **billing**, **CI**, and **production-adjacent** repositories — **as long as they remain strictly read-only** (no state change beyond local compute and reading bytes):

- **read** / **list** / **search** / **inspect** / **analyze** / **report** (and equivalent verbs: view, cat, show metadata, dry inventory, read-only API queries).

**Rule — gated per matrix (`policies/auto-approve-matrix.md`) and `policies/autonomy-policy.json`:**

The following always require explicit human approval **or** an approved steward path **before** execution, never “silent autonomy”:

- **write** / **apply** / **delete** / **migrate** / **deploy** / **commit** / **push** / **release**
- **secret handling** / **policy relaxation** / **validator bypass**
- any change that would weaken `neverTreatAsPassed` semantics or validation honesty.

**Non-goals:** This section does **not** authorize remote mutation, production writes, or bypassing ledger/approval rules. It **does** authorize agents to **stop asking humans for permission** to read or audit critical-path material when the operation is strictly read-only.

## Task contract

Before editing, every agent must know:

1. **Scope** — target files / subsystem.
2. **Intent** — bugfix, feature, audit, validation, docs, release, incident.
3. **Critical surfaces** — auth, security, CI, release, filesystem, permissions, production, payments, secrets, PII.
4. **Validation path** — the cheapest reliable command(s) that prove the change.
5. **Rollback path** — how to revert safely.

If any item is unknown, start with read-only discovery and keep it bounded.

## Token economy

Named-file or small-scope tasks must use surgical mode:

- no broad repository discovery by default;
- no sub-agents / wide scans unless justified;
- read target files, direct imports, direct tests, and immediate contracts first;
- use path-scoped diffs and targeted tests;
- keep reports compact and evidence-backed.

Broad discovery is reserved for explicit repo-wide audit, architecture/security review, unknown incident scope, or user-approved exploration.

## Patch discipline

- Make the smallest complete patch that satisfies the task.
- Preserve untouched behavior and formatting where possible.
- Avoid opportunistic cleanup.
- Add or update regression tests when behavior changes.
- Do not introduce new dependencies without explicit justification and approval.
- Do not change generated artifacts unless the generator/source of truth is also understood.
- Split unrelated findings into follow-up tasks.

## Safety

- **no secrets** — never commit or paste tokens, keys, or PII into logs or markdown.
- **no raw stack traces** in user-facing summaries — keep diagnostics short and redacted.
- **no false green** — do not report success when a fallback, skip, or partial validation occurred.
- **no hidden destructive action** — deletes, overwrites, permission changes, and environment changes require explicit approval.

## Git (hard negatives)

- **no git add .** — stage explicit paths.
- **no `git push --force`** — do not `git push --force` or `--force-with-lease` on shared default branches without approval.
- **no stash pop** without reviewing `git stash show` first.
- **no reset hard / clean** unless explicitly directed and rollback is understood.

## Validation ladder

1. Targeted syntax/type check for touched files.
2. Targeted unit/integration tests for changed behavior.
3. Contract/schema/runtime validators for manifests, policies, generated scaffolds, or OS runtime changes.
4. Full suite only when risk or coupling justifies it.

If validation is skipped or unavailable, say so explicitly and give the exact command the human should run.

## Close-out

- **validate before close** — run project/OS validation scripts expected for the change.
- **summarize evidence** — changed files, tests, residual risks, rollback.
- **record durable learning** with `session-absorb` / `session-digest` when project state or policy changed.

## Human approval required (mutations and policy)

Runtime mutation, bootstrap that changes trust boundaries, **writes** to validation/CI/security/release surfaces, filesystem-destructive operations, production-impacting edits, and **policy relaxation** require **human approval** per `policies/auto-approve-matrix.md` and `requiresHumanApproval.surfaces` in `policies/autonomy-policy.json`. Read-only audits on those surfaces do **not** require pre-approval (L4).
