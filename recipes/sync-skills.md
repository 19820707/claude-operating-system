# Recipe: Sync skills to adapters

## Objective

Copy canonical `source/skills/*/SKILL.md` into declared `generatedTargets` with the standard generated header.

## When to use

- After editing any canonical skill, or when CI shows skills drift — contract in [SKILLS.md](../docs/SKILLS.md).

## Commands

```powershell
pwsh ./tools/sync-skills.ps1 -DryRun -Json
pwsh ./tools/sync-skills.ps1 -Json
pwsh ./tools/verify-skills-drift.ps1 -Json
```

## Expected result

- Dry-run lists targets as **unchanged** or **copied** as expected; drift checker **ok** (or only warns on body drift before sync).

## Acceptable warnings

- Drift **warn** on non-strict runs when copies were stale until you apply sync.

## Unacceptable warnings/failures

- Sync writes outside `skills-manifest.json` `generatedTargets`, or drift **fail** under **Strict** after sync.

## Next step if it fails

1. Confirm `skills-manifest.json` lists the paths you intend to write.
2. Re-run sync; if still drift, check newline/header rules in `verify-skills-drift.ps1` and canonical file encoding.
3. See [production-safety.md](../policies/production-safety.md) before forcing writes in sensitive trees.
