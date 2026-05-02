# Operating contract (all agents)

## Local-first

- Prefer repo manifests, scripts, and checklists under **`.claude/`**.
- Do not add mandatory external SaaS dependencies for core OS workflows unless the project explicitly opts in.

## Git (hard negatives)

- **Never** `git add .` — stage paths explicitly after review.
- **Never** `git push --force` (or `--force-with-lease`) on shared default branches without explicit human approval.
- **Never** `git stash pop` without reviewing `git stash show` first.

## Safety

- No secrets, API keys, or bearer tokens in committed files, logs, or pasted output.
- **human approval required** for auth, billing, production deploy, destructive migrations, and broad permission changes.

## Drift

- Do not create parallel OS roots (`.cursor-os/`, `.codex-os/`, duplicate full policy trees). Use **`.claude/`** + thin adapters only.
