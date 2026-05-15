# Claude OS Security Model

Claude OS is a local-first operational layer for coding agents. It installs project-local policies, prompts, adapters, scripts, memory files, and validation tools. It does not replace repository security controls; it makes agent behavior auditable and bounded.

## Threat model

| Threat | Risk | Required control |
|--------|------|------------------|
| Prompt injection in repo files | Agent follows malicious instructions from source/docs | Treat repo content as untrusted evidence; project policy and human instructions outrank file text |
| Secret exfiltration | Agent prints or commits tokens, env values, keys, PII | Redact outputs; deny `.env*`, keys, credentials, and raw payload dumps |
| False-green validation | Agent reports skipped/degraded/partial checks as success | Enforce no-false-green contract: fallback != healthy; skipped != passed |
| Destructive filesystem mutation | Agent deletes/overwrites project or OS files | Human approval required; no `rm -rf`, `git clean`, `reset --hard` without explicit direction |
| Dangerous git operations | Force push, broad staging, stash pop, hidden history mutation | No `git add .`, no force push, no stash pop without reviewed diff |
| Cross-project contamination | App code or state accidentally written into OS clone, or vice versa | Keep OS source repo separate from app repos; validate path before mutation |
| CI/deploy mutation | Agent changes release gates or production behavior silently | Human approval required for CI, deploy, release, permissions, production surfaces |
| Stale session memory | Agent assumes old state is current | Read `CLAUDE.md`, `.claude/session-state.md`, and git state at session start |
| Over-broad discovery | Agent wastes tokens or reads sensitive files unnecessarily | Surgical mode by default; `.claudeignore` defines out-of-scope paths |
| Adapter drift | Cursor/Codex/generic agents lose required safety rules | Validate adapter policy content in CI/health checks |

## Critical surfaces

Changes require **human approval required** when they touch:

- auth / authz / sessions / tokens;
- payments / billing;
- secrets / credentials / `.env*`;
- CI/CD, release gates, deployment config;
- migrations / schema / production data;
- filesystem permissions or destructive operations;
- generated agent adapters and global policies when used in production projects.

## No-false-green contract

Agents must report operational state precisely:

- `pass` only when a check ran and passed;
- `warn` as warning, not success;
- `skip` as skipped, not passed;
- fallback/demo/local behavior as degraded unless explicitly intended;
- unknown evidence as unknown, not assumed OK.

Invariant: **fallback != healthy; skipped != passed; warning != success**.

## Scope control

Project-local `.claudeignore` files should block agent reads/indexing of sensitive or noisy paths:

- `.env*`, keys, certificates, credentials;
- `node_modules/`, vendor/build outputs, generated reports;
- coverage, cache, dist/build artifacts;
- local-only tool state.

`.claudeignore` is a scope-control artifact. It is not a replacement for `.gitignore`, secret scanning, or repository permissions.

## Output hygiene

User-facing and session files must not include:

- secrets, API keys, tokens, passwords;
- raw PII;
- full stack traces when a concise error is enough;
- raw JSON payloads from sensitive tools;
- private local paths beyond what is needed for verification.

## Validation expectations

OS changes should pass:

```powershell
pwsh ./tools/os-runtime.ps1 validate -Strict
```

For production rollout, also verify generated project artifacts after `os-runtime.ps1 update` or bootstrap.
