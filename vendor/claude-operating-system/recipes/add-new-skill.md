# Recipe: Add a new skill

## Objective

Add a **canonical** skill under `source/skills/` and keep manifests, bootstrap counts, and generated copies aligned.

## When to use

- You need a new agent skill contract — full process in [SKILLS.md](../docs/SKILLS.md); use [SKILL.template.md](../templates/skills/SKILL.template.md) as the skeleton.

## Commands

```powershell
# After adding source/skills/<id>/SKILL.md and editing skills-manifest.json + bootstrap-manifest.json:
pwsh ./tools/verify-skills.ps1
pwsh ./tools/verify-skills-manifest.ps1 -Json
pwsh ./tools/sync-skills.ps1 -DryRun -Json
pwsh ./tools/sync-skills.ps1 -Json
pwsh ./tools/verify-skills-drift.ps1 -Strict -Json
```

## Expected result

- `verify-skills` and `verify-skills-manifest` **ok**; drift **match** after sync.

## Acceptable warnings

- `verify-skills-structure` may **warn** on non-**Strict** runs during migration; resolve before release.

## Unacceptable warnings/failures

- Duplicate skill ids, missing `examples`/`tests` or exemption, missing policy paths, drift **fail** under **Strict**.

## Next step if it fails

1. Fix manifest or frontmatter per verifier output.
2. Re-read [SKILLS.md](../docs/SKILLS.md) “Adding a skill” and bump [INDEX.md](../INDEX.md) counts if `verify-doc-manifest` requires it.
3. Never hand-edit generated copies — use `sync-skills.ps1`.
