# Validation incident runbook

Use this when `pwsh ./tools/os-validate-all.ps1` or `pwsh ./tools/verify-os-health.ps1` fails in CI or locally. Commands assume repository root.

## Exit codes and JSON

| Verifier | OK | Fail |
|----------|----|------|
| `verify-os-health.ps1` | `0` | `1` (any failed check, or `-Strict` with disallowed warnings) |
| `verify-git-hygiene.ps1` | `0` | `1` if hard failures; with `-Strict`, hygiene warnings are promoted to failures before exit |
| `verify-json-contracts.ps1` | `0` | `1` |

Machine-readable aggregate health:

```powershell
pwsh ./tools/verify-os-health.ps1 -Json 2>$null
```

The last line of **stdout** is a single JSON object (envelope: `name`, `status`, `strict`, `checks[]`, `failures`, `warnings`, `totalMs`, `repo`). Host and script chatter often lands on **stderr**; redirect stderr when piping JSON to a file or parser.

## Health (`verify-os-health`) fails

1. Re-run with JSON and stderr discarded: `pwsh ./tools/verify-os-health.ps1 -Json 2>$null`
2. Open the envelope: `status` is `fail` if any check failed; under `-Strict`, `status` can be `fail` when only warnings remain on allowed checks (for example doctor latency soft-budget) after hard failures are fixed.
3. Map `checks[].name` to the isolated command below.
4. If `bootstrap-real-smoke` failed, inspect temp path in the error text; ensure `init-project.ps1` is not blocked by AV or locked paths.

## Doctor fails or is slow

- Blocking: `pwsh ./tools/os-doctor.ps1 -Json` must show `"status":"ok"` (or `warn` without failing checks). Exit non-zero means blocking failures.
- Latency: health records **WARN** if doctor wall time exceeds **10s**, **FAIL** if it exceeds **30s** after completion. Hung doctor is not force-killed; treat as OS/process issue.
- Bash: without bash on PATH, doctor may skip bash checks unless `-RequireBash` is set on health.

## Git hygiene fails

```powershell
pwsh ./tools/verify-git-hygiene.ps1 -Json
```

- Nested `claude-operating-system/` at repo root: **WARN** locally, **FAIL** under `-Strict` or CI.
- `-Strict` also elevates all other hygiene warnings (dirty tree, ahead/behind) to failures after the synthetic failure line is added.
- Recovery: `GIT-RECOVERY.md` / `docs/GIT-RECOVERY.md`.

## Bash missing

- Symptom: health shows `bash-syntax` **skip** with note `bash not found on PATH`, or `-RequireBash` aborts early.
- Fix: install Git for Windows or WSL bash and ensure `bash` is on PATH; CI images should install bash before `-RequireBash`.

## Bootstrap smoke fails

- Symptom: `bootstrap-real-smoke` fails in health.
- Isolate: run `init-project.ps1 -ProjectPath` to a new empty temp directory with `-SkipGitInit` and compare `bootstrap-manifest.json` `projectBootstrap.criticalPaths` to the tree produced.

## Agent adapters fail

```powershell
pwsh ./tools/verify-agent-adapters.ps1
pwsh ./tools/verify-agent-adapters.ps1 -Json
```

- Fix manifest vs `templates/adapters/` drift; every adapter `runtimePath` must be `.claude/`.

## JSON contract fails

```powershell
pwsh ./tools/verify-json-contracts.ps1
```

- Align schemas and JSON files with allowed surfaces in the verifier script.

## OS read-only invariants fail

```powershell
pwsh ./tools/verify-os-invariants.ps1
pwsh ./tools/verify-os-invariants.ps1 -Json
```

- Catches manifest drift (managed artifacts, adapter runtime paths, bootstrap anti-patterns, adapter template whitelist).
