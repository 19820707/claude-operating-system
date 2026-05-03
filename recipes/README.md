# Claude OS recipes

Short, repeatable **command + expectation** cards. Full policy and rationale live in **[docs/](../docs/)** and **[policies/](../policies/)** — recipes link there instead of inlining large blocks.

## Index

| Recipe | Purpose |
|--------|---------|
| [validate-local-quick.md](validate-local-quick.md) | Fast `quick` validation |
| [validate-release-strict.md](validate-release-strict.md) | Strict / release gates |
| [initialize-project.md](initialize-project.md) | New project scaffold |
| [add-new-skill.md](add-new-skill.md) | New canonical skill |
| [sync-skills.md](sync-skills.md) | Regenerate skill copies |
| [repair-adapter-drift.md](repair-adapter-drift.md) | Fix skills + adapter drift |
| [prepare-release.md](prepare-release.md) | Pre-tag checklist |

## Manifest

Entries live in **`recipe-manifest.json`** (schema: **`schemas/recipe-manifest.schema.json`**).

## Verify

```powershell
pwsh ./tools/verify-recipes.ps1 -Json
pwsh ./tools/verify-recipes.ps1 -Strict -Json
```
