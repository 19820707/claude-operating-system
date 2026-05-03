# Operating contract (all agents)

## Principles

- **local-first** — prefer repo manifests and scripts; no new mandatory external SaaS for core OS flows.
- **artifact-first** — commit deliberate artifacts; stage paths explicitly after review.
- **deterministic validation** — use repo checklists and `pwsh`/scripted gates where provided.
- **human-gated critical surfaces** — auth, security, CI, release, filesystem, permissions, production, payments.
- **token-proportional execution** — read and validate only what the task requires.
- **fail-closed critical behavior** — never convert a critical failure into silent success.

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

## human approval required

Runtime, bootstrap, validation, CI, security, filesystem, and production-impacting edits require **human approval required**.
