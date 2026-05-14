# Adapters after `init-project.ps1`

Generated (or refreshed) **project-facing** adapter surfaces:

| Path | Role |
|------|------|
| `AGENTS.md` | From `templates/adapters/AGENTS.md` (unless skipped without `-Force`). |
| `.cursor/rules/claude-os-runtime.mdc` | Cursor rules; always refreshed from OS templates. |
| `.agent/runtime.md`, `handoff.md`, `operating-contract.md` | Agent runtime contract pack. |
| `.agents/OPERATING_CONTRACT.md` | Legacy plural path; thin pointer per `policies/multi-tool-adapters.md`. |

Do not commit secrets into these files; treat them like any other tracked markdown.
