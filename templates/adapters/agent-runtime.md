# Runtime overview (.claude/)

This document is **neutral** reference for any agent (Codex, Cursor, other). It does **not** replace `.claude/`; it describes how to use it.

## What lives in `.claude/`

| Area | Purpose |
|------|---------|
| `session-state.md` | Live branch, decisions, risks, next steps |
| `learning-log.md` | Cumulative learning and heuristics |
| `decision-log.jsonl` | Append-only decision records |
| `workflow-manifest.json` | Progressive delivery gates |
| `os-capabilities.json` | Capability registry for routing |
| `scripts/` | Installed OS tools (prime, route, workflow, validators, hooks) |
| `policies/` | Project policy copies and critical-surface checklists |
| `skills/` | Installed skill artifacts |

## Principle

**One runtime.** Tool-specific files (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) only explain *how to enter* this tree — they are not a second source of truth.
