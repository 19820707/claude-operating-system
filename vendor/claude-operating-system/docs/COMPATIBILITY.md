# Platform compatibility

Claude OS tooling is **PowerShell-first**. Most validators are plain `tools/*.ps1` files intended to run under **PowerShell 7 (`pwsh`)** on Windows, Linux, and macOS. A smaller set of orchestrators also probe **Bash** when it is on `PATH` (optional on Windows; typical on Linux CI).

Canonical machine-readable data lives in **`compatibility-manifest.json`** (see **`schemas/compatibility-manifest.schema.json`**). **`tools/verify-compatibility.ps1`** checks that:

- every validator implied by **`script-manifest.json`** is declared in the compatibility manifest;
- there are no extra or duplicate validator rows;
- each validator inherits **`defaultSupport`** and optional per-tool **`overrides`** for all platform dimensions;
- **`platformCatalog`** ids match the platform keys in **`defaultSupport`**.

Run: `pwsh ./tools/verify-compatibility.ps1` or `pwsh ./tools/verify-compatibility.ps1 -Json`.

## Platform dimensions

| Id | Meaning |
|----|---------|
| `win-ps-5.1` | **Windows PowerShell 5.1** (`powershell.exe`). Orchestrators may still spawn `pwsh` children; leaf scripts are not routinely tested under 5.1 as the host. |
| `win-pwsh` | **PowerShell 7 on Windows** — primary desktop target. |
| `linux-pwsh` | **PowerShell 7 on Linux** — typical for local dev and **GitHub Actions `ubuntu-latest`** when `pwsh` is installed. |
| `macos-pwsh` | **PowerShell 7 on macOS**. |
| `bash-on-path` | **POSIX Bash** available on `PATH` (native Linux/macOS, or WSL userland). |
| `git-bash` | **Git for Windows** Bash (MINGW64 / MSYS). |
| `wsl` | **WSL** distro: validators invoked from Windows with Linux userland via WSL. |
| `gha-ubuntu` | **GitHub Actions** Linux runner (same practical expectations as `linux-pwsh` + `bash-on-path`). |
| `gha-windows` | **GitHub Actions** Windows runner (`pwsh` preinstalled; Bash optional). |

## Support levels

| Level | Meaning |
|-------|---------|
| `supported` | Expected to work for normal repo workflows on that dimension. |
| `best-effort` | May work with caveats (missing optional commands, host quirks, or strict timing). |
| `not-applicable` | The dimension is irrelevant for that validator (for example most leaf scripts never invoke Bash). |
| `unsupported` | Reserved for cases we explicitly do not support (none by default). |

**Default row** (inherited by all validators unless **`overrides`** are set):

| Dimension | Level |
|-----------|--------|
| `win-ps-5.1` | `best-effort` |
| `win-pwsh` | `supported` |
| `linux-pwsh` | `supported` |
| `macos-pwsh` | `supported` |
| `bash-on-path` | `not-applicable` |
| `git-bash` | `not-applicable` |
| `wsl` | `not-applicable` |
| `gha-ubuntu` | `supported` |
| `gha-windows` | `supported` |

**Orchestrators with optional Bash** (`verify-os-health.ps1`, `os-validate.ps1`, `os-validate-all.ps1`, `os-doctor.ps1`) use **`overrides`** so `bash-on-path`, `git-bash`, and `wsl` are **`best-effort`**: Bash syntax and template checks may **skip** or **warn** when Bash is missing instead of pretending the surface passed.

## CI and local validation

- **`os-validate.ps1`** (all profiles) runs **`verify-compatibility.ps1 -Json`** in the first JSON tool batch.
- **`verify-os-health.ps1`** runs **`verify-compatibility.ps1`** after **`verify-doc-contract-consistency`**.
- **`verify-json-contracts.ps1`** and **`run-contract-tests.ps1`** assert **`compatibility-manifest.json`** pairs with its schema.

## Adding or renaming a validator

1. Add or update the tool under **`script-manifest.json`** (path `tools/verify-*.ps1`, or one of the documented exceptions: `test-skills`, `run-contract-tests`, `evaluate-quality-gate`, `os-doctor`, `os-validate`, `os-validate-all`).
2. Add a matching **`{ "id": "…" }`** entry to **`compatibility-manifest.json`** `validators` array (defaults only, or include **`overrides`** / **`notes`**).
3. Run `pwsh ./tools/verify-compatibility.ps1 -Json`.

See also **`docs/VALIDATION.md`** (profiles) and **`INDEX.md`** (tool index).
