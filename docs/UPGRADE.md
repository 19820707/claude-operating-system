# Upgrade notes (contracts)

Claude OS tracks **breaking and contract-level** changes in two places:

1. **`docs/UPGRADE.md`** (this file) — human-oriented summary and workflow.
2. **`upgrade-manifest.json`** — machine-readable records consumed by **`pwsh ./tools/verify-upgrade-notes.ps1`**.

Release and strict validation require that every watched root JSON contract whose **`schemaVersion`** was raised is covered by at least one manifest **entry** whose **`contractBumps`** declare a **maximum** `schemaVersion` for that path **greater than or equal to** the value on disk.

## Watched contracts

The watched set is the union of:

- Every JSON ↔ schema pair validated by **`tools/verify-json-contracts.ps1`** (root manifests such as `os-manifest.json`, `bootstrap-manifest.json`, … `distribution-manifest.json`).
- **`session-memory-manifest.json`** (root `schemaVersion`, same semantics).
- **`upgrade-manifest.json`** itself (so format bumps to this file are also documented).

The authoritative ordered list lives in **`upgrade-manifest.json` → `watchedContractFiles`**. It must stay aligned with the verifier (the script fails if the list drifts).

## When you bump a contract

For each bump of **`schemaVersion`** on any watched file (or when you introduce a new watched file at version ≥ 1):

1. Add a new object to **`upgrade-manifest.json` → `entries`** with:
   - **`id`** — stable kebab-style identifier.
   - **`versionIntroduced`** — SemVer or tag for the release that ships the change.
   - **`summary`** — short description of the contract change.
   - **`affectedFiles`** — repo-relative paths (manifests, schemas, tools, docs) touched by the change.
   - **`migrationSteps`** — concrete steps for consumers (forks, downstream scaffolds, CI).
   - **`rollbackGuidance`** — how to revert safely (git revert, which files, what to re-run).
   - **`validationCommand`** — a single **`pwsh ./tools/...`** command that proves the migration (often **`pwsh ./tools/verify-upgrade-notes.ps1 -Json -Strict`** plus a targeted verifier).
   - **`contractBumps`** — one `{ "path", "schemaVersion" }` per watched JSON file whose **documented** contract version increases with this change (use the **new** integer `schemaVersion` after your edit).

2. If **`schemas/upgrade-manifest.schema.json`** or the **shape** of **`upgrade-manifest.json`** changes, bump **`upgrade-manifest.json` → `schemaVersion`** and include **`upgrade-manifest.json`** in **`contractBumps`** for that entry.

3. Summarize the same change in this **`docs/UPGRADE.md`** file under a dated or versioned heading so humans can skim history.

## Commands

| Goal | Command |
|------|---------|
| Strict gate (fail on drift) | `pwsh ./tools/verify-upgrade-notes.ps1 -Json -Strict` |
| Warn-only (e.g. local triage) | `pwsh ./tools/verify-upgrade-notes.ps1 -Json` |

## Baseline

Initial tracking for schemaVersion **1** across all watched manifests is recorded as entry **`contract-tracking-baseline-1-0-0`** in **`upgrade-manifest.json`**.
