# AGENTS.md — multi-agent contract (Codex / generic agents)

This file is a **thin adapter**. The **operational source of truth** is **`.claude/`** (session, workflow, capabilities, checklists, scripts).

## Read order (start of work)

1. **`.claude/session-state.md`** — branch, decisions, risks, next steps (do not assume chat history).
2. **`.claude/learning-log.md`** — patterns and heuristics from prior work.
3. **`.claude/workflow-manifest.json`** — phase gates for this repo.
4. **`.agent/runtime.md`** and **`.agent/handoff.md`** — how adapters relate to the shared runtime.

## Rules

- **Local-first**: prefer repo scripts and manifests; no new external services for core OS flows.
- **Secrets**: never print or commit secrets, tokens, or connection strings.
- **Git hygiene**: do not use `git add .`; do not `git push --force` on shared branches; review stash before apply.
- **Production and critical surfaces**: **human approval required** before irreversible or customer-impacting changes.

## Anti-patterns

- A second “OS root” (e.g. `.cursor-os/`, `.codex-os/`) parallel to `.claude/` — causes drift.
- Duplicating full policy corpora here — keep this file short; link into `.claude/policies/` instead.

See also: **`policies/multi-tool-adapters.md`** in the `claude-operating-system` repo for the full hybrid model.
