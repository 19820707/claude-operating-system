# Deprecation policy

Claude OS uses **`deprecation-manifest.json`** at the repository root as the **authoritative registry** of deprecated:

- **Scripts** (`tools/*.ps1` paths)
- **Skills** (canonical `source/skills/<id>` identifiers)
- **Documentation** (paths such as `docs/…` or index targets)
- **Manifest JSON keys** (per-file `manifestPath` + `jsonKey`)
- **Slash commands** (`templates/commands/<name>.md`)

Every deprecated entry **must** declare:

| Field | Meaning |
|--------|---------|
| **replacement** | What callers should use instead |
| **deprecatedSince** | ISO date the item was marked deprecated |
| **removalNotBefore** | Earliest date removal may occur (governance) |
| **reason** | Why it is deprecated |
| **migrationInstructions** | Concrete steps for consumers |
| **allowedInStrictMode** | If `false`, the item must **not** appear on default validation surfaces (see below) |

## Enforcement

**`pwsh ./tools/verify-deprecations.ps1`** validates the manifest (required fields, date ordering, unique ids) and, with **`-Strict`**, **fails** when a deprecated artifact with **`allowedInStrictMode: false`** is still referenced on:

1. **Default validation orchestration** — text scan of **`tools/os-validate.ps1`** and **`tools/os-validate-all.ps1`** for `tools/…ps1` script paths.
2. **Manifest-governed release gates** — raw scan of **`quality-gates/*.json`** for validator `script` paths and other embedded paths.

Without **`-Strict`**, the same hits are reported as **warnings** only (envelope status `warn` when `-Json`).

Strict profile (`**pwsh ./tools/os-validate.ps1 -Profile strict**`), **`verify-os-health`**, and **`quality-gates/release.json`** (via **`evaluate-quality-gate -Gate release`**) run deprecations in **`-Strict`** mode so CI and release paths cannot depend on forbidden deprecated scripts or gates.

## Optional upstream comparison

To align capabilities with another fork (example: **`19820707/claude-operating-system`**), clone **outside** tracked content, e.g.:

```powershell
git clone --depth 1 https://github.com/19820707/claude-operating-system.git extern-reference/upstream-19820707
```

The **`extern-reference/`** directory is **gitignored** in this repo. Compare manifests and validators manually; fold differences into **`deprecation-manifest.json`** and normal PR workflow—do not vendor the whole upstream tree into the canonical OS root.

## Related

- **`docs/QUALITY-GATES.md`** — release gate semantics.
- **`docs/VALIDATION.md`** — profiles and status taxonomy.
