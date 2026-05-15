# Runtime overview — one tree, many adapters

## `.claude/` is the common runtime

Session memory, workflow gates, capability registry, checklists, copied policies, and installed scripts live under **`.claude/`**. Every agent must treat that directory as the **only** operational root.

## Adapters (thin; no second runtime)

| Surface | Role |
|---------|------|
| **`CLAUDE.md`** | Adapter for **Claude Code** — how to read and honour `.claude/`. |
| **`AGENTS.md`** | Adapter for **Codex / generic agents** — read order and commands; still defers to `.claude/`. |
| **`.cursor/rules/`** (e.g. `claude-os-runtime.mdc`) | Adapter for **Cursor** — Project Rules that reference the same paths. |
| **`.agent/`** (`runtime.md`, `handoff.md`, `operating-contract.md`) | **Tool-neutral** prose — contract and handoff; not a parallel runtime. |
| **`.agents/OPERATING_CONTRACT.md`** (optional) | **Legacy pointer** only — defers to **`.agent/operating-contract.md`**; same adapter layer, not a second runtime. |

Nothing in the adapters replaces manifests under **`.claude/`**; they only explain how to use them.
