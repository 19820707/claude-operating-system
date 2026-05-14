# Recipe: Repair adapter drift

## Objective

Bring `.claude/`, `.cursor/`, and related generated trees back in line with canonical sources using sync tools.

## When to use

- `verify-agent-adapter-drift` or `verify-skills-drift` reports problems — deeper runbook: [adapter-drift-repair.md](../playbooks/adapter-drift-repair.md); adapter policy: [multi-tool-adapters.md](../policies/multi-tool-adapters.md).

## Commands

```powershell
pwsh ./tools/verify-skills-drift.ps1 -Json
pwsh ./tools/sync-skills.ps1 -Json
pwsh ./tools/sync-agent-adapters.ps1
pwsh ./tools/verify-agent-adapter-drift.ps1 -Json
pwsh ./tools/verify-skills-drift.ps1 -Strict -Json
```

## Expected result

- Drift tools report **ok** / match after sync; no writes outside manifest-declared targets.

## Acceptable warnings

- Git-dirty warnings from hygiene tools if you are only regenerating tracked adapter copies locally.

## Unacceptable warnings/failures

- **Strict** drift fail after sync, sync touching undeclared paths, or merge with known adapter false-green.

## Next step if it fails

1. Diff canonical vs generated; canonical wins unless an approved exception exists.
2. Re-read [SKILLS.md](../docs/SKILLS.md) and [multi-tool-adapters.md](../policies/multi-tool-adapters.md).
3. Get human approval before **Release**/**Destructive** sync per [production-safety.md](../policies/production-safety.md).
