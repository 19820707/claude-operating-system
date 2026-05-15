# Capabilities and intent routing

Claude OS separates two complementary registries:

| Artifact | Purpose |
|----------|---------|
| **`os-capabilities.json`** | Fine-grained **os.*** capabilities: single entrypoints, skills, risk/cost, and legacy `validations` strings. Used by workflow phases and session tooling. |
| **`capability-manifest.json`** | **Intent routes** (`route.*`): map a *kind of work* to operating mode, risk, approval tier, skills, playbooks, validators, evidence expectations, and forbidden shortcuts. |

Both are validated by **`pwsh ./tools/verify-capabilities.ps1`**. JSON Schema: `schemas/os-capabilities.schema.json` and `schemas/capability-manifest.schema.json`.

## Router CLI

From the OS repo (or a bootstrapped project with `.claude/` scripts), run:

```powershell
pwsh ./tools/route-capability.ps1 -ListRoutes
pwsh ./tools/route-capability.ps1 -Query "strict validation"
pwsh ./tools/route-capability.ps1 -RouteId route.release
pwsh ./tools/route-capability.ps1 -Id os.health
pwsh ./tools/route-capability.ps1 -Tag security -Limit 5
pwsh ./tools/route-capability.ps1 -Query bootstrap -Json
```

**`-Query`** prefers **intent routes** when `capability-manifest.json` is present, then fills with **`os.***` capabilities** until `-Limit`. **`-ListTags`** merges tags from routes and capabilities.

JSON output shape:

```json
{
  "kind": "intent-routes | registry-capabilities | mixed | none",
  "count": 1,
  "results": [ { "kind": "intent-route", "id": "route.bootstrap", "...": "..." } ]
}
```

## Intent routes (required set)

| Route id | Focus |
|----------|--------|
| `route.release` | Release gate, strict validation, playbooks |
| `route.incident` | Incident response, break-glass posture |
| `route.migration` | Data/platform migration with gates |
| `route.bootstrap` | `init-project` / `.claude` scaffold |
| `route.docs-audit` | Doc contract, INDEX, false-green avoidance |
| `route.adapter-drift` | Adapter sync and drift checks |
| `route.skill-authoring` | Canonical `source/skills` changes |
| `route.strict-validation` | `os-validate` strict + `os-validate-all` |
| `route.security-review` | Security policy and adapter boundaries |

Each route declares **`operatingMode`** (`read-only`, `standard`, `strict`, `controlled-change`, `break-glass`, `release-gate`), **`riskLevel`**, **`requiredApproval`** (`none`, `peer`, `maintainer`, `security`, `incident-command`), **`relevantSkills`** (directories under `source/skills/`), **`relevantPlaybooks`** (ids from `playbook-manifest.json`), **`validators`** (safe `pwsh ./tools/...` commands only), **`expectedEvidence`**, **`forbiddenShortcuts`**, and **`docs`** (ids from `docs-index.json`). Routes tagged **`ci`**, **`production`**, **`security`**, or other critical surfaces must not use **`requiredApproval: none`** (enforced by `verify-capabilities.ps1`).

## Managed project copies

`init-project.ps1` and **`pwsh ./tools/os-update-project.ps1`** install **`capability-manifest.json`** beside **`os-capabilities.json`** under **`.claude/`** so local **`route-capability.ps1`** resolves the same contracts as the OS repo.

## Related docs

- `docs/VALIDATION.md` — profiles (quick / standard / strict) and false-green rules.
- `docs/RELEASE-READINESS.md` — release evidence expectations.
- `playbooks/README.md` — playbook index and verifier.
- `ARCHITECTURE.md` — high-level placement of manifests and tools.
