# Recipe: Validate local (quick)

## Objective

Get a fast green signal on contracts, skills, playbooks, recipes, and bootstrap counts without full release aggregate.

## When to use

- Before pushing a small change, or when you only need the **quick** profile described in [VALIDATION.md](../docs/VALIDATION.md).

## Commands

```powershell
pwsh ./tools/os-validate.ps1 -Profile quick -Json
```

Optional detail:

```powershell
pwsh ./tools/verify-recipes.ps1 -Json
```

## Expected result

- `os-validate` envelope `status` is **ok** and process exit code **0**.
- Skills, playbooks, and recipes verifiers report **ok** when run individually.

## Acceptable warnings

- None for **quick** when the tree is clean; if a nested tool emits **warn**, treat as non-green per [runtime-budget.json](../runtime-budget.json) and [VALIDATION.md](../docs/VALIDATION.md).

## Unacceptable warnings/failures

- Any **fail** status, missing manifest, or non-zero exit on the commands above for a change you intend to merge.

## Next step if it fails

1. Read the JSON `failures` / `warnings` on the failing tool line.
2. Fix manifests or docs called out, then re-run. For skills/playbooks/recipes shape issues, see [SKILLS.md](../docs/SKILLS.md) and [playbooks/README.md](../playbooks/README.md).
3. If bootstrap counts fail, align `bootstrap-manifest.json` and [INDEX.md](../INDEX.md) per [doc contract](../policies/multi-tool-adapters.md) tooling.
