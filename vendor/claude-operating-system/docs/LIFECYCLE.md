# Lifecycle: install, init, update, repair, rollback, uninstall, and project flows

This document is the human-facing companion to **`lifecycle-manifest.json`** (validated by **`tools/verify-lifecycle.ps1`**). Every lifecycle command in the manifest declares:

| Field | Intent |
|-------|--------|
| **writes** | What paths, repos, or artifacts change on disk or in git. |
| **backups** | What safety nets exist (git history, stash, operator archives) versus what is **not** automated. |
| **idempotency** | Whether re-running is safe, partial, or context-dependent. |
| **rollbackBehavior** | How to undo or recover (git, restore archives, re-bootstrap). |
| **validationAfterExecution** | Concrete checks after the operation (health, hygiene, bootstrap verifiers, project CI). |

Canonical structured data: **`lifecycle-manifest.json`**. Run `pwsh ./tools/verify-lifecycle.ps1 -Json` after edits.

## Phases (required coverage)

| Phase | Meaning in this repo |
|-------|----------------------|
| **install** | Copy global policy assets into `~/.claude` (`install.ps1` / `install.sh`). |
| **init** | Idempotent **OS checkout** setup: workspace context, operator journal, `logs/`, adapter sync (`tools/init-os-runtime.ps1`, also `pwsh ./tools/os-runtime.ps1 init`). |
| **update** | Bring the **OS repository** current with upstream (git workflows; **`GIT-RECOVERY.md`**). |
| **repair** | Reduce Git friction before pulls (`tools/git-recover-local.ps1`). |
| **rollback** | Policy-first recovery for bad merges/rebases (**`GIT-RECOVERY.md`**); human-gated destructive git. |
| **uninstall** | **Manual** removal of global `~/.claude` and/or project `.claude` / adapter surfaces (no bundled uninstall script). |
| **project-bootstrap** | Scaffold an app repo with the full managed `.claude` tree (`init-project.ps1` via `os-runtime.ps1 bootstrap`). |
| **project-update** | Refresh **managed** OS artifacts inside an existing app repo (`tools/os-update-project.ps1` via `os-runtime.ps1 update`). |

## Dispatcher entrypoints

Many flows are reached through **`tools/os-runtime.ps1`**:

- `init` → `init-os-runtime.ps1`
- `bootstrap` → `init-project.ps1` (requires `-ProjectPath`)
- `update` → `os-update-project.ps1` (requires `-ProjectPath`)
- `validate` → `os-validate.ps1` (profiles) or `os-validate-all.ps1` when no profile is given

Use **`-DryRun`** where supported (`install`, `init-project`, `os-update-project`, `init-os-runtime`) to preview writes.

## Validation wiring

- **`os-validate.ps1`** (all profiles) runs **`verify-lifecycle.ps1 -Json`** in the early JSON tool batch.
- **`verify-os-health.ps1`** runs **`verify-lifecycle`** after **`verify-compatibility`**.
- **`verify-json-contracts.ps1`** and **`run-contract-tests.ps1`** require **`lifecycle-manifest.json`** + **`schemas/lifecycle-manifest.schema.json`** to exist and parse.

## Changing lifecycle behavior

1. Update the **PowerShell/bash** implementation and this doc.
2. Update **`lifecycle-manifest.json`** so fields stay accurate (especially **writes** and **validationAfterExecution**).
3. Run `pwsh ./tools/verify-lifecycle.ps1 -Json`.

See also **`GIT-RECOVERY.md`**, **`docs/VALIDATION.md`**, **`docs/COMPATIBILITY.md`**, and **`docs/PROJECT-BOOTSTRAP.md`**.
