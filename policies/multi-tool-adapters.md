# Multi-tool runtime — one truth, thin adapters

Applies when **Claude Code**, **Cursor**, and **Codex** (or similar agents) touch the **same repository**. Goal: **no drift** between three parallel “operating systems”.

---

## Verdict (hybrid)

| Layer | Role |
|--------|------|
| **`.claude/`** | **Single operational source of truth** — session state, learning log, workflow, capabilities, checklists, policies, validation scripts. |
| **Adaptadores** | **Tool-specific read/instruction surfaces only** — how each product loads and defers to that truth. |

Do **not** split into three roots of truth (e.g. `.claude/` + `.cursor-os/` + `.codex-os/`). That creates conflicting phase, stash, learning, and policy state.

---

## Recommended layout (project repo)

```text
<project>/
├── .claude/              # runtime comum (estado, políticas copiadas, scripts)
├── CLAUDE.md             # adaptador Claude Code — fino; aponta para .claude/
├── AGENTS.md             # adaptador Codex / agentes — fino; aponta para .claude/
├── .cursor/rules/        # adaptador Cursor — regras automáticas; apontam para .claude/
└── .agent/               # (opcional) documentação neutra multi-agente partilhada
```

- **`CLAUDE.md`** — how Claude Code should **read and honour** `.claude/` (session order, modes, gates).
- **`AGENTS.md`** — how agent runtimes should **use** shared contracts without duplicating full policy corpora.
- **`.cursor/rules/*.mdc`** — Cursor-native rules that **reference** the same session/workflow/checklist paths under `.claude/` (concrete example: `.cursor/rules/claude-os-runtime.mdc`).
- **`.agent/`** — optional **neutral** multi-agent docs (contracts, diagrams) that are **not** a second runtime tree.

### Per-tool stacks (how adapters combine)

| Tool | Read / instruct via | Shared runtime |
|------|----------------------|----------------|
| **Claude Code** | `CLAUDE.md` + native `.claude/` usage | `.claude/` |
| **Cursor** | `.cursor/rules/` (e.g. `claude-os-runtime.mdc`) + **`AGENTS.md`** for shared agent context | `.claude/` |
| **Codex / advanced agents** | **`AGENTS.md`** (thin contract: how to use the OS) + **`.agent/`** (optional neutral docs) | `.claude/` |

`AGENTS.md` can be **shared** across Cursor and Codex because it should stay **thin**: pointers into `.claude/`, not a second policy corpus.

---

## What must stay shared

Single copy under **`.claude/`** (or paths explicitly installed there by bootstrap):

- Session continuity (`session-state.md`, `learning-log.md`, …)
- Decisions / workflow / capabilities / checklists / security policies
- Validation and hook scripts consumed by the repo

If each tool keeps **its own** copy of that state, you get: divergent phase, duplicate decisions, contradictory rules, and silent learning-log drift.

---

## What must stay thin

Avoid three fat policy files:

- ~~`CLAUDE.md` + `CURSOR.md` + `CODEX.md` each with full duplicated rules~~

Prefer **thin** root files that **point** into `.claude/policies/` and global install docs.

---

## Anti-patterns

| Anti-pattern | Why it fails |
|--------------|--------------|
| `.cursor-os/`, `.codex-os/` parallel to `.claude/` | Multiple sources of truth; CI and humans cannot reconcile. |
| Full policy duplication per tool | Drift on every edit; merge pain. |
| Cursor-only or Codex-only session state outside `.claude/` | Same code, incompatible mental model of “where we are” in the workflow. |

---

## Bootstrap note (this repository)

Project templates today reference a **neutral multi-agent contract** under **`.agents/OPERATING_CONTRACT.md`** in some command headers and `templates/project-CLAUDE.md`. That folder plays the same **adapter / neutral contract** role as **`.agent/`** in the model above; renaming or converging paths is a **separate, explicit migration** (manifest + `init-project` + existing repos), not implied by this policy alone.

---

## Operational rule

**`.claude/` = operational truth.**  
**Root markdown + `.cursor/rules/` + `.agent/` (or `.agents/`) = how each tool enters that truth — not a second runtime.**

For production-impacting layout or bootstrap changes: **human approval required**.
