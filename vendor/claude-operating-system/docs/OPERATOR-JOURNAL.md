# Operator journal

The **operator journal** is a **local, gitignored** Markdown file at the repository root: **`OPERATOR_JOURNAL.md`**.

## Why it exists

- Capture **failed validations**, **audit observations**, and **local decisions** without polluting committed docs.
- Record **environment-specific** notes (paths, shells, CI parity) that do not belong in `README.md`.
- Complement **`OS_WORKSPACE_CONTEXT.md`** (local workspace context): the journal is **time-ordered narrative**; the workspace context file is **current defaults and tables**.

## Rules

1. **Never commit** `OPERATOR_JOURNAL.md` — it is listed in **`.gitignore`**.
2. **No secrets** — same bar as `OS_WORKSPACE_CONTEXT.template.md`: no tokens, keys, PII, or full env dumps.
3. **Created automatically** — `pwsh ./tools/init-os-runtime.ps1` copies **`OPERATOR_JOURNAL.template.md`** → **`OPERATOR_JOURNAL.md`** when the journal is missing (use **`-DryRun`** to preview without writing).

## Template

Authoritative structure and starter tables live in **`OPERATOR_JOURNAL.template.md`** at repo root. Edit the generated **`OPERATOR_JOURNAL.md`** freely; to reset structure only, compare against the template (do not delete unique history without a backup).
