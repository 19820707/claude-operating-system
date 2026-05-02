# Session handoff protocol

Bounded session memory is driven by the installed scripts under **`.claude/scripts/`**. Canonical bases (prime → absorb → digest): **session-prime**, **session-absorb**, **session-digest** (each has a matching `*.ps1` in that folder).

1. **`session-prime.ps1`** — load bounded context (`-Json` supported) before deep work.
2. **`session-absorb.ps1`** — append a short operational note to **`.claude/learning-log.md`** (`-Note`, `-Kind`).
3. **`session-digest.ps1`** — append end-of-session summary to learning log and **`.claude/decision-log.jsonl`** (`-Summary`, `-Outcome`, etc.).

## Rules

- Keep notes **short** and **evidence-based**; no secrets in logs.
- Do not replace **`.claude/`** state with chat-only memory — update the files above.

**human approval required** for changes that alter retention, PII handling, or audit policy for these logs.
