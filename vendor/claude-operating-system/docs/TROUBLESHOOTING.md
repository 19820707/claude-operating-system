# Troubleshooting Claude OS

Use this guide with **`pwsh ./tools/os-doctor.ps1 -Json`** and **`pwsh ./tools/verify-os-health.ps1 -Json`** (add `-SkipBootstrapSmoke` for a faster loop while iterating). Each non-green check includes **reason**, **impact**, **remediation**, **strictImpact**, and a **docs** pointer in JSON where the tooling supports it.

---

## No Git checkout

**Symptoms:** `verify-git-hygiene` warns or skips; adapter drift cannot prove cleanliness; some validators assume a Git work tree.

**Why:** Folder is a zip extract, partial copy, or worktree without `.git`.

**Fix:** `git init` / clone properly, or pass **`verify-git-hygiene -WarnIfNoGit`** only where policy allows. For drift, commit or revert changes under `templates/adapters` and generated adapter paths. See `docs/VALIDATION.md` (profiles).

---

## Bash missing on Windows

**Symptoms:** `os-doctor` warns on **bash**; `verify-os-health` **bash-syntax** is **skip**; strict Ubuntu CI expects Bash.

**Why:** Default Windows PATH often has no `bash.exe`.

**Fix:** Install **Git for Windows** (includes Git Bash) or **WSL**, ensure `bash` is on PATH, re-run doctor. For local-only runs, **`verify-os-health -SkipBashSyntax`** or **`os-doctor -SkipBashSyntax`** matches the documented Windows path; do not treat that as a release substitute on Linux CI.

---

## PowerShell version mismatch

**Symptoms:** `os-doctor` fails **powershell** (pwsh not found); parsers behave differently on Windows PowerShell 5.1 vs PowerShell 7.

**Why:** Claude OS validators target **PowerShell 7+** (`pwsh`).

**Fix:** Install [PowerShell 7+](https://github.com/PowerShell/PowerShell), use `pwsh` for all `tools/*.ps1` entrypoints. Run `pwsh --version` and confirm PATH in a **new** terminal.

---

## Adapter drift

**Symptoms:** `verify-agent-adapter-drift` warns or fails; uncommitted changes under `templates/adapters` or manifest-listed generated targets.

**Why:** Edited generated or template adapters without syncing or committing.

**Fix:** Review `git status`, run **`pwsh ./tools/sync-agent-adapters.ps1`** where appropriate, commit intentional changes, or revert accidental edits. Use **`-FailOnDrift`** only when policy should hard-fail (see `docs/VALIDATION.md`).

---

## Skill drift

**Symptoms:** `verify-skills-drift` or `verify-skills-manifest` non-zero; `skills-manifest.json` disagrees with `source/skills/`.

**Why:** New/changed skills on disk without manifest updates, or canonical vs generated targets out of sync.

**Fix:** Update **`skills-manifest.json`**, run **`pwsh ./tools/verify-skills.ps1`**, **`verify-skills-structure`**, and **`sync-skills.ps1`** as needed. Re-read `docs/SKILLS.md`.

---

## JSON schema failure

**Symptoms:** `verify-json-contracts` or `verify-doc-contract-consistency` fails; manifests reject schema shape.

**Why:** Edited JSON by hand, wrong `schemaVersion`, or drift between `os-manifest.json` entrypoints and files on disk.

**Fix:** Run **`pwsh ./tools/verify-json-contracts.ps1`** and fix the first reported path. Compare your file to **`schemas/*.schema.json`**. Keep `$schema` and `schemaVersion` aligned with repo conventions (`docs/VALIDATION.md`).

---

## ARCHITECTURE / runtime-release mismatch

**Symptoms:** `verify-runtime-release` fails; `VERSION` ≠ `os-manifest.json` `runtime.version`; required substrings missing from `ARCHITECTURE.md`, `CHANGELOG.md`, or `SECURITY.md`.

**Why:** Release contract text is part of the governance gate (`validationPolicy.releaseContract` in `os-manifest.json`).

**Fix:** Align **`VERSION`** with **`os-manifest.json`**, restore required phrases from `os-manifest.json` into the three docs, then re-run **`pwsh ./tools/verify-runtime-release.ps1`**. See **`ARCHITECTURE.md`** and **`CHANGELOG.md`** headers for intent.

---

## Generated file manually edited

**Symptoms:** Drift validators flag paths under `.claude/`, `.cursor/`, or adapter templates; merge conflicts in generated SKILL copies.

**Why:** Generated artifacts were edited without updating canonical sources (`source/skills/`, `templates/`, manifests).

**Fix:** Move durable changes into **canonical** files, regenerate via **`init-project.ps1`** / **`sync-skills.ps1`** / **`sync-agent-adapters.ps1`**, and avoid hand-editing generated trees except during deliberate hotfixes (then sync back or document an exception). See `docs/RELEASE-READINESS.md` when applicable.

---

## Still stuck

1. **`pwsh ./tools/os-doctor.ps1 -Json`** — environment and scaffold signals.  
2. **`pwsh ./tools/verify-os-health.ps1 -Json -SkipBootstrapSmoke`** — aggregate contract health (faster iteration).  
3. **`docs/VALIDATION.md`**, **`docs/EXAMPLES.md`**, **`docs/AUDIT-EVIDENCE.md`** — profiles, sample envelopes, sanitized audit export.
