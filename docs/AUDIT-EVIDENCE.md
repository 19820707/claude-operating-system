# Audit evidence export

Operators and release owners can capture a **sanitized, machine-readable** snapshot of Claude OS validation posture without dumping secrets, environment values, or local scratchpad contents.

## Command

From the repository root:

```bash
pwsh ./tools/export-audit-evidence.ps1 -OutputPath ./exports/my-audit-run
```

### Parameters

| Parameter | Purpose |
|-----------|---------|
| **`-OutputPath`** (required) | Directory to create or reuse. Relative paths resolve under the repo root. |
| **`-Json`** | After writing files, print `audit-evidence-manifest.json` to stdout (UTF-8 JSON, one line). |
| **`-IncludeStrictValidation`** | Also runs `os-validate -Profile strict -Json` (slower; may exit non-zero; envelope is still captured when JSON is emitted). |
| **`-SkipBashSyntax`** | Forwarded to `os-validate` for both quick and strict profiles when `-IncludeStrictValidation` is used. |

## Outputs

Inside `-OutputPath`:

| File | Description |
|------|-------------|
| **`audit-evidence-manifest.json`** | Inventory: timestamps, privacy flags, per-section `collected` / `exitCode`, SHA-256 and byte length of the bundle. Schema: `schemas/audit-evidence-manifest.schema.json`. |
| **`evidence-bundle.json`** | Consolidated summaries and validator envelopes (nested JSON). Not separately schema-validated; shape is documented here and stable for tooling. |

## What is collected (sanitized)

- **os-manifest summary** — `schemaVersion`, runtime name/version (truncated), description snippet, manifest/entrypoint **key names** only, managed artifact count.
- **runtime profiles summary** — Profile ids, command counts, truncated purpose text, defaults.
- **validation results** — `os-validate -Profile quick -Json` envelope (and strict when requested). Child processes may exit `1` on warn/fail; stdout JSON is still parsed when present.
- **skills manifest summary** — `schemaVersion`, `canonicalRoot` (redacted), skill count, skill ids, maturity histogram (no full file paths beyond repo-relative strings).
- **adapter drift** — `verify-agent-adapter-drift.ps1 -Json` envelope.
- **git hygiene** — `verify-git-hygiene.ps1 -Json -WarnIfNoGit` envelope (avoids hard failure when `.git` is missing).
- **PowerShell version** — `PSVersionTable` subset and short OS description snippet (redacted).
- **Bash availability** — Whether `bash` is on PATH; no shell profile contents.
- **OS summary** — `OSVersion` string (redacted), 64-bit flag, processor count, tick count (non-identifying).
- **Timestamp** — UTC ISO-8601 on bundle and manifest.
- **Command versions** — First line of `git --version`, `pwsh --version`, and `bash --version` when available (each passed through `Redact-SensitiveText`).

## What is never collected

- **Environment variable values** — not enumerated; no `%ENV%` dump.
- **Secrets** — strings are passed through `Redact-SensitiveText` (`tools/lib/safe-output.ps1`) where user-facing text is assembled.
- **`.env`** — only a boolean **presence** flag; the file is never read.
- **`OS_WORKSPACE_CONTEXT.md` full text** — only **metadata**: exists or not, line count, byte length.
- **Raw stack traces with sensitive paths** — only short, redacted error snippets if a summary step fails.

The manifest **`privacy`** block records these invariants (`environmentVariableValuesIncluded`, `dotEnvContentsIncluded`, `osWorkspaceContextFullTextIncluded`, and `secretsEmitted` are always `false` by policy).

## Verification

- JSON Schema for the manifest: `schemas/audit-evidence-manifest.schema.json` (checked by `pwsh ./tools/verify-examples.ps1` via `examples/audit/audit-evidence-manifest-minimal-example.json`).
- Default export directory name `exports/` is **gitignored** (see `.gitignore`) so audit runs are not committed by accident; choose any path you intend to archive.

## Related

- `docs/EXAMPLES.md` — sample validator envelopes.
- `docs/VALIDATION.md` — profiles and exit semantics for `os-validate`.
