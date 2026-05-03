# Multi-tool runtime — one truth, thin adapters

Applies when **Claude Code**, **Cursor**, and **Codex** (or similar agents) touch the **same repository**. Goal: **no drift** between three parallel “operating systems”.

---

## Verdict (hybrid)

| Layer | Role |
|--------|------|
| **`.claude/`** | **Single operational source of truth** — session state, learning log, workflow, capabilities, checklists, policies, validation scripts. |
| **Adaptadores** | **Tool-specific read/instruction surfaces only** — how each product loads and defers to that truth. |

Do **not** split into three roots of truth (e.g. `.claude/` + `.cursor-os/` + `.codex-os/`). That creates conflicting phase, stash, learning, and policy state.

In the **claude-operating-system** repo, the adapter map is also declared in **`agent-adapters-manifest.json`** (schema: `schemas/agent-adapters.schema.json`) and checked by **`tools/verify-agent-adapters.ps1`** (`-Json` supported) so the layer stays manifest-governed like the rest of the runtime.

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

Project templates today reference a **neutral multi-agent contract** under **`.agents/OPERATING_CONTRACT.md`** in some command headers and `templates/project-CLAUDE.md`. **`init-project.ps1` / `os-update-project.ps1`** install a **thin pointer** at that path that defers to **`.agent/operating-contract.md`** (canonical). Treat both as the same adapter layer — **not** a second runtime under `.claude/`.

---

## Repository separation (OS source vs application work)

The **`claude-operating-system`** clone on disk is the **distribution source**: templates, manifests, `tools/os-update-project.ps1`, validators. It is **not** where application product code should live.

| Do | Why |
|----|-----|
| Keep **features, fixes, and product tests** only in each **application repository** (e.g. Rallyo-Platform). | Preserves one git history, correct CI, and clear ownership. |
| From the **OS clone**, run `pwsh ./tools/os-runtime.ps1 update -ProjectPath <path-to-app>` (or `os-update-project.ps1`) to **refresh managed OS files inside the app**. | Reads from the OS tree, writes into the app tree — no need to nest repos. |
| Use a **separate terminal or workspace** per root: either you are in the **OS clone** (pull, validate, `update` out) or in the **app repo** (prime, digest, build). | Avoids wrong-`cwd` commits and path confusion. |

| Do **not** | Why it fails |
|-----------|--------------|
| Nest an application repo **inside** `claude-operating-system/` (e.g. `claude-operating-system/claude-operating-system/`). | Triggers hygiene failures, ambiguous remotes, and accidental edits in the wrong tree. |
| Treat the OS clone as the **working tree** for an unrelated product. | Risk of committing app changes to the OS repo or polluting OS `main` with product noise. |
| Run **`init-project.ps1 -ProjectPath`** pointing at the OS clone **for product work**. | `init-project` scaffolds a **project** layout; the OS repo already *is* the source layout. |

For production-impacting bootstrap/update behaviour or changing this separation: **human approval required**.

---

## Operational rule

**`.claude/` = operational truth.**  
**Root markdown + `.cursor/rules/` + `.agent/` (or `.agents/`) = how each tool enters that truth — not a second runtime.**

For production-impacting layout or bootstrap changes: **human approval required**.

---

## External reference — Arcads (patterns only)

**Arcads** may be used **only** as a reference for **observable operating patterns**: idempotent setup; **local, gitignored** working context; **canonical skills** under a single source tree with **generated** Claude/Cursor (and similar) copies; a **manifest-driven sync** path; **local** references and logs (not committed secrets); **`.env` hygiene**; a **thin `AGENTS.md`**; and **simple onboarding** docs.

Anything **beyond** that set—validators, quality gates, playbooks, upgrade ledger, distribution contracts, capability routing, strict profiles, or other OS machinery—is **Claude OS–specific engineering**. It must **not** be described or justified as “copied from Arcads” or assumed to match Arcads unless explicitly documented as a deliberate port with its own review.
