# Distribution packaging

Claude OS ships as a **source repository**. The distribution pack is a **portable zip** of the subset needed to install, bootstrap projects, and run validators offline, without copying developer-local state.

## Manifest and resolver

| Artifact | Role |
|----------|------|
| **`distribution-manifest.json`** | Declares **rootFiles**, **includeTrees** (recursive directories), **excludePathRegexes** (POSIX-style `/` paths), **mandatoryPackagedPaths** (smoke checks), and output paths. |
| **`schemas/distribution-manifest.schema.json`** | JSON Schema for the manifest. |
| **`tools/lib/distribution-resolve.ps1`** | Dot-sourced resolver: expands trees, applies regex excludes, returns a sorted unique path list. |

## Commands

| Script | Purpose |
|--------|---------|
| **`tools/verify-distribution.ps1`** | Read-only: every **rootFile** and mandatory path exists; regexes compile; resolved pack contains mandatory paths; rough sanity on `tools/*.ps1` count. Supports **`-Json`**. |
| **`tools/build-distribution.ps1`** | Resolves the same file set, stages under **`stagingDirectoryRelative`**, runs **`Compress-Archive`** to **`outputZipRelative`**, then deletes the staging folder. Supports **`SupportsShouldProcess`** — use **`-WhatIf`** (or `-Confirm:$false`) to preview without writing the zip. Supports **`-Json`**. |

Typical preview:

```powershell
pwsh ./tools/build-distribution.ps1 -WhatIf -Json
pwsh ./tools/verify-distribution.ps1 -Json
```

Production pack (writes **`dist/`**; ignored by git — see `.gitignore`):

```powershell
pwsh ./tools/build-distribution.ps1 -Json
```

## What is included

- **Policies, prompts, heuristics** — `policies/`, `prompts/`, `heuristics/`.
- **Manifests** — root `*.json` contracts (bootstrap, OS, skills, workflows, budgets, gates, etc.) listed in **`rootFiles`**.
- **Schemas** — `schemas/**/*.json`.
- **Tools** — all of **`tools/`** (including **`tools/lib/*.ps1`**).
- **Templates** — `templates/` except **`templates/invariant-engine/node_modules/`** (dev-only).
- **Canonical skills** — `source/skills/`.
- **Operational docs** — `docs/`, `playbooks/`, `recipes/`, `examples/`, plus root markdown and `install.*` / `init-project.ps1`.

## What is excluded

Paths matching **`excludePathRegexes`** are dropped from the pack, including:

- Local workspace context and journal (**`OS_WORKSPACE_CONTEXT.md`**, **`OPERATOR_JOURNAL.md`**).
- **`logs/`**, **`local-evidence/`**, **`evidence/local/`**, **`exports/`**.
- **`.env` / `.env.*`**, **`settings.local.json`**, **`*.local-backup.ps1`**.
- Generated skill mirrors at repo root (**`.claude/skills/`**, **`.cursor/skills/`**, **`.codex/skills/`**) — canonical skills live under **`source/skills/`**; mirrors are recreated by bootstrap/sync where needed.
- **`tests/`** — CI and scratch fixtures; not required to operate the runtime from a zip.
- **`.git/`**, nested clone paths (**`extern-reference/`**, **`claude-operating-system/`**), and **`dist/`** staging/zip paths to avoid self-inclusion.

## CI and profiles

- **`verify-distribution`** runs in **`os-validate.ps1`** (all profiles) and **`verify-os-health.ps1`**.
- **`verify-json-contracts.ps1`** / **`run-contract-tests.ps1`** assert the manifest/schema pair exists.
- **`quality-gates/release.json`** includes **`verify-distribution`** before strict aggregate validation.

When you add a **new root-level manifest** or a **required operational doc**, update **`distribution-manifest.json`** (`rootFiles`, `mandatoryPackagedPaths`, or `includeTrees`) and re-run **`verify-distribution.ps1 -Json`**.
