# Operating contract (all agents)

## Principles

- **local-first** — prefer repo manifests and scripts; no new mandatory external SaaS for core OS flows.
- **artifact-first** — commit deliberate artifacts; stage paths explicitly after review.
- **deterministic validation** — use repo checklists and `pwsh`/scripted gates where provided.
- **human-gated critical surfaces** — auth, security, CI, release, filesystem, permissions, production, payments.

## Safety

- **no secrets** — never commit or paste tokens, keys, or PII into logs or markdown.
- **no raw stack traces** in user-facing summaries — keep diagnostics short and redacted.

## Git (hard negatives)

- **no git add .** — stage explicit paths.
- **no `git push --force`** — do not `git push --force` or `--force-with-lease` on shared default branches without approval.
- **no stash pop** without reviewing `git stash show` first.

## Close-out

- **validate before close** — run project/OS validation scripts expected for the change (e.g. `pwsh ./tools/os-validate-all.ps1 -Strict` in the OS repo).

## human approval required

Runtime, bootstrap, validation, CI, security, filesystem, and production-impacting edits require **human approval required**.
