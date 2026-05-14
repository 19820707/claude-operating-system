# Project bootstrap (init-project)

`init-project.ps1` scaffolds a **consumer repository** from a checked-out **Claude OS** repo: it copies manifests, skills, policies, commands, scripts, session-memory templates, adapter surfaces, and optional invariant-engine bundles. The contract is driven by **`bootstrap-manifest.json`** (`projectBootstrap.criticalPaths` and `projectBootstrap.scripts`).

## Operator commands

```powershell
# Typical (Windows): new empty folder, then bootstrap from OS clone
powershell -ExecutionPolicy Bypass -File .\init-project.ps1 -ProjectPath "C:\work\my-service" [-Profile node-ts-service|react-vite-app] [-SkipGitInit] [-Force]
```

- **`-Force`**: overwrites `CLAUDE.md` / `AGENTS.md` from templates when they already exist; adapter files under `.cursor/`, `.agent/`, `.agents/` are refreshed from templates regardless.
- **`-SkipGitInit`**: skips `git init` (used by health smoke tests and zip-style trees).
- **`-DryRun`**: lists actions without writing.

## What appears under `.claude/`

| Area | Contents |
|------|-----------|
| **Routing** | `docs-index.json`, `os-capabilities.json`, `capability-manifest.json`, `deprecation-manifest.json`, `workflow-manifest.json` |
| **Scripts** | Copies of `tools/query-docs-index.ps1`, `route-capability.ps1`, `workflow-status.ps1`, session scripts, and every `*.sh` listed in the bootstrap manifest |
| **Session memory** | `session-state.md`, `learning-log.md`, `settings.json`, empty `decision-log.jsonl`, optional `decision-log.schema.json` |
| **Commands / agents** | Markdown from `templates/commands` and `templates/agents` |
| **Skills** | Each `source/skills/<id>/` copied to `.claude/skills/<id>/` |
| **Policies** | `policies/*.md` plus `templates/critical-surfaces/*.md` into `.claude/policies/` |
| **Invariant engine** | `.cjs` bundles when present under `templates/invariant-engine/dist/` |
| **Profiles** | `.claude/stack-profile.md` when `-Profile` is set |

## Adapters (multi-tool)

After init, the project root includes **`AGENTS.md`**, **`.cursor/rules/claude-os-runtime.mdc`**, **`.agent/*.md`**, and **`.agents/OPERATING_CONTRACT.md`**. Treat them as **managed** surfaces: refresh from OS templates rather than one-off manual drift.

## Decision log (JSONL)

Append-only **`.claude/decision-log.jsonl`**. Each line is one JSON object; required fields are defined in **`templates/local/decision-log.schema.json`** (`id`, `ts`, `type`, `trigger`, `policy_applied`, `decision`, plus optional arrays).

## Reference examples (no secrets)

Under **`examples/project-bootstrap/`**:

- **`minimal/`** — directory tree description, session/learning stubs, sample JSONL, command/policy/skill READMEs, adapter summary.
- **`advanced/`** — adds stack-profile sample, invariant-engine README, session-memory overview, and an additional JSONL sample.

Validate anytime:

```bash
pwsh ./tools/verify-bootstrap-examples.ps1
```

## Related docs

- `docs/QUICKSTART.md` — Windows path and strict CI path.
- `docs/TROUBLESHOOTING.md` — generated file drift and bootstrap failures.
- `docs/AUDIT-EVIDENCE.md` — sanitized export of validation posture.
