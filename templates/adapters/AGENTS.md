# AGENTS.md — Codex / generic agents (Claude OS Runtime)

This project uses **Claude OS Runtime**. The operational source of truth is **`.claude/`** — not this file.

## Before you edit

Read, in order:

1. **`CLAUDE.md`** — project-level policy and how Claude Code expects work to run.
2. **`.claude/session-state.md`** — branch, decisions, risks, next steps (do not assume chat history).
3. **`.claude/workflow-manifest.json`** — phase gates for this repo.
4. **`.claude/os-capabilities.json`** — capability routing and automation boundaries.

## Commands to prefer (installed under `.claude/scripts/`)

- **Prime (bounded context):**
  `pwsh .claude/scripts/session-prime.ps1`
- **Route a task:**
  `pwsh .claude/scripts/route-capability.ps1 -Query "<task>"`
- **Workflow status:**
  `pwsh .claude/scripts/workflow-status.ps1 -Phase verify`
- **Close session:**
  `pwsh .claude/scripts/session-digest.ps1 -Summary "<summary>" -Outcome passed`

Also use **session-absorb** during work when you learn something durable:
`pwsh .claude/scripts/session-absorb.ps1 -Note "<note>" -Kind ops`

## Git and safety (hard negatives)

- Do **not** use `git add .`, `git push --force`, or `git reset --hard` without explicit human direction.
- Do **not** run `git stash pop` without reviewing the stash diff first.
- Do **not** delete backups or whole directories without human review.

## human approval required

**human approval required** before changes to auth, security, CI, release, filesystem layout, permissions, production systems, or payments — and whenever policy says so.

See **`.agent/runtime.md`**, **`.agent/handoff.md`**, and **`.agent/operating-contract.md`** for the shared neutral contract.
