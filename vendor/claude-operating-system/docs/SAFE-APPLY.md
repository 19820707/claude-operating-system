# Safe apply (mutating tools)

Claude OS mutating scripts must support **preview** and **declared write surfaces** so operators and CI can avoid silent disk changes.

## Requirements (contract)

| Requirement | How |
|-------------|-----|
| Dry-run or WhatIf | Implement **`[switch]$DryRun`** and/or **`[CmdletBinding(SupportsShouldProcess = $true)]`** with **`$PSCmdlet.ShouldProcess`**, and/or **`[switch]$WhatIf`** so callers can preview work. |
| Confirm for destructive paths | Prefer **SupportsShouldProcess** so PowerShell’s **`-WhatIf`** / **`-Confirm`** pipeline works; document any manual overwrite rules in the script header. |
| Declared writes | List human-readable paths or surfaces in **`script-manifest.json`** `writes[]` for every tool that creates or overwrites files. |
| Generated targets | Use optional **`safeApply.generatedWriteTargets`** for stable descriptions of outputs (especially manifest-driven copies). |
| Rollback | Use optional **`safeApply.rollbackNote`** for how to undo or re-sync after a real run. |
| JSON summary | When a tool supports **`-Json`**, include **planned or executed writes** in the envelope (e.g. `actions`, `findings`, or a dedicated field) so **`invoke-safe-apply.ps1 -Json`** can surface them next to the wrapper summary. |

## Wrapper: `invoke-safe-apply.ps1`

Resolve a tool by **`script-manifest.json`** `id`, forward **`-DryRun`** or **`-WhatIf`** when the target script supports them, and emit a small JSON summary of declared writes and exit code:

```powershell
pwsh ./tools/invoke-safe-apply.ps1 -ToolId sync-skills -DryRun -Json
pwsh ./tools/invoke-safe-apply.ps1 -ToolId os-update-project -DryRun -PassArgs @('-ProjectPath','D:\tmp\my-app')
```

If the target lacks any dry-run family, the wrapper **throws** before invoking (see `tools/lib/safe-apply.ps1`).

## Validation

- **`tools/verify-script-manifest.ps1`** warns when a tool **declares `writes[]`** but the script body has no **`-DryRun` / `-WhatIf` / SupportsShouldProcess** (see `tools/lib/safe-apply.ps1`).
- **`pwsh ./tools/verify-script-manifest.ps1 -Strict`** (used from **`os-validate.ps1 -Profile strict`** and **`verify-os-health.ps1 -Strict`**) **fails** when **`writeRisk`** is **`high`** and the script still lacks that dry-run family.

## `writeRisk` tiers

| Value | Meaning |
|-------|---------|
| `none` | Default when `writes[]` is empty; no safe-apply finding row. |
| `low` / `medium` | Optional explicit tier; non-empty `writes[]` defaults to **medium** for messaging only. |
| `high` | Bulk or project-wide mutation (**strict** requires dry-run family). |

Set **`writeRisk`** explicitly for high-impact tools (`sync-skills`, `os-update-project`, `export-audit-evidence`, …) so strict CI stays honest.
