# Contract tests (manifests, docs, scripts)

This directory holds **data** used by **`tools/run-contract-tests.ps1`** (allowlists and keyword maps). The runner itself lives under **`tools/`** so it can be invoked like other verifiers.

| File | Purpose |
|------|--------|
| **`strict-profile-allowlist.json`** | Tool ids (`script-manifest.json` **id**) that may remain **experimental** or **deprecated** while still referenced from **`os-validate.ps1`** strict paths (normally empty). |
| **`release-evidence-keywords.json`** | Maps **`quality-gates/release.json`** `requiredEvidence` lines to **`requiredValidators`** entries by substring keyword. Optional **`humanOnlyEvidenceSubstrings`**: evidence lines matching those substrings skip the validator keyword rule (human checklist text). |

Keep **`release-evidence-keywords.json`** aligned when editing release gate evidence text.
