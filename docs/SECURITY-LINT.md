# Security lint (secrets and sensitive data)

This repository ships **`tools/verify-no-secrets.ps1`**, a read-only checker for obvious credentials and a small set of ambiguous patterns. It complements `verify-security-policy.ps1` (policy text contracts) and `verify-claudeignore.ps1` (ignore hygiene).

## Philosophy

- **Fail** on high-confidence matches (private key blocks, well-known provider key shapes, tracked `.env*` files, missing `/logs/` ignore rules).
- **Warn** on ambiguous matches (long `Bearer` fragments, JWT-shaped dot triples, `api_key=` / `token=` style assignments in prose or examples). Warnings exit **0** unless you pass **`-Strict`**, which promotes warnings to failures (used by `os-validate.ps1` **strict** profile and by `verify-os-health.ps1` when `-Strict` is set).

False positives are possible; the JSON envelope lists `warnings`, `failures`, and structured `findings` (file, line, rule id). Snippets are redacted via `Redact-SensitiveText`.

## What is checked

| Area | Behavior |
|------|----------|
| Git index | Paths matching committed **`.env` / `.env.*`** (requires `.git`; otherwise a single **warn** explains the limitation). |
| `.gitignore` | Must include an active **`/logs/`** (or equivalent) rule so generated JSONL/log trees stay untracked. |
| PEM / PKCS | Lines matching **`-----BEGIN … PRIVATE KEY-----`**. |
| Provider-shaped keys | AWS `AKIA` / `ASIA`, Google `AIza…`, Stripe `sk_live_` / `rk_live_`, GitHub `ghp_` / `github_pat_`, Slack `xox…`, Anthropic `sk-ant-api03-`, OpenAI `sk-proj-` (minimum tail length). |
| Markdown and examples | Same fail patterns plus **warn-tier** assignment and token shapes on **`.md`**; JSON/YAML/TXT/TOML/SH under scanned trees get fail + warn patterns where applicable. |
| `OS_WORKSPACE_CONTEXT.template.md` | Included in every run (must stay free of real secrets). |
| `examples/` | Covered via directory walk and via `git ls-files` for tracked text extensions. |
| Large / binary files | Skipped (extension allowlist under `templates/` avoids scanning bundled `.cjs`). |

Intentional probe strings live only in **`tools/verify-os-health.ps1`**, **`tools/lib/safe-output.ps1`**, and this script; those files are excluded from pattern scanning.

## Commands

```powershell
pwsh ./tools/verify-no-secrets.ps1
pwsh ./tools/verify-no-secrets.ps1 -Json
pwsh ./tools/verify-no-secrets.ps1 -Json -Strict
```

**Profiles:** `os-validate.ps1` **standard** and **strict** invoke `-Json`; **strict** also passes **`-Strict`**. `verify-os-health.ps1` runs the tool after Git hygiene, forwarding `-Strict` when the health run is strict.

## Fixing findings

- **Tracked `.env`:** remove from Git (`git rm --cached`) and rely on local-only env files; `.gitignore` already lists `.env` / `.env.*`.
- **PEM / keys:** never commit material keys; use secret managers or CI secrets; replace doc examples with placeholders like `REDACTED` or split keys (`…first4…last4`).
- **Warn-tier in docs:** prefer `your_api_key_here`, `***`, or environment variable names without values.

See also `SECURITY.md` (threat model) and `docs/VALIDATION.md` (profiles).
