# CLAUDE.md — [PROJECT NAME]

Global engineering policies apply from `~/.claude/CLAUDE.md`.
This file contains only project-specific context.

---

## Session Continuity — READ FIRST

At the start of every session:
1. Read `~/.claude/CLAUDE.md` (global policies + learning system)
2. Read `.claude/session-state.md` (branch, decisions, risks, next steps)
3. Read `.claude/learning-log.md` (phase patterns, heuristics, anti-patterns)
4. Do not assume state from chat history

At the end of every session: update `.claude/session-state.md`.
At the end of every phase: append to `.claude/learning-log.md` via `/phase-close`.

---

## Project Context

**Stack:** <!-- e.g. Node.js / TypeScript / React / PostgreSQL -->
**Branch model:** <!-- e.g. main (production) / develop (active) -->
**Platform:** <!-- e.g. Vercel / AWS / Hostinger -->

---

## Repo-Specific Policies

| Policy | File |
|--------|------|
| Operating modes | `.claude/policies/operating-modes.md` |
| Model selection (with project surfaces) | `.claude/policies/model-selection.md` |
| Engineering governance | `.claude/policies/engineering-governance.md` |
| Production safety | `.claude/policies/production-safety.md` |

---

## Critical Surfaces (Opus mandatory)

<!-- List the specific files/modules in this project that require Opus -->
<!-- Example: -->
<!-- - `src/auth/engine.ts` -->
<!-- - `src/billing/gateway.ts` -->

---

## Active Roadmap

<!-- Current phase and epic sequence -->
<!-- See `.claude/session-state.md` for detail -->

---

## Agents

<!-- List agents available in .claude/agents/ -->

---

## Engineering OS — Auto-injected context

@.claude/session-state.md
@.agents/OPERATING_CONTRACT.md
@.claude/heuristics/operational.md
