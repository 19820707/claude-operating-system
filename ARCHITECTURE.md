# ARCHITECTURE — Claude OS Runtime

Claude OS Runtime is a local-first engineering runtime for Claude-driven projects. It turns a repository into a governed agent workspace with manifests, skills, policies, workflow gates, validation, and bootstrap/update tooling.

## Operational positioning

Claude OS Runtime is **local-first operational governance** for engineering agents. It is **not** a substitute for CI/CD, GitHub Actions, human review, or formal production control.

Its role is to **improve AI-assisted engineering quality** through explicit contracts, reproducible validations, context management, capability synchronization, audit trails, and **human gates** on critical surfaces.

Claude OS must **not** try to become an autonomous production agent. It functions as **control, containment, and verification infrastructure**, so that any agent operating on a repository does so within limits that are **clear, observable, and auditable**.

### Where this layer sits

```text
Human / engineering team
        ↓
Claude Code / Cursor / Codex / other agents
        ↓
Claude OS runtime governance  (manifests, validators, `.claude/` runtime)
        ↓
Project repository
        ↓
Formal CI/CD, GitHub Actions, human review, production
```

The objective is **not** to replace the formal systems below this layer. The objective is to **raise the quality of what reaches them**.

**Operational capability roadmap (Portuguese):** target ten-step flow (§2–§11), **technical capability map (§14)**, **maturity (§15)**, **upstream outcome (§16)**, **agent autonomy model A0–A4 / 95–5 design goal (§17)** — [`docs/CAPACIDADES-OPERACIONAIS.md`](docs/CAPACIDADES-OPERACIONAIS.md).

**Autonomy layer (English, machine contracts):** [`docs/AUTONOMY.md`](docs/AUTONOMY.md), `policies/autonomy-policy.json`, `tools/os-autopilot.ps1`, `tools/verify-autonomy-policy.ps1`.

## What Claude OS is not

These boundaries keep the runtime aligned with **governance and verification**, not with owning formal delivery or production authority.

**Portuguese:** the same non-goals are spelled out in project language in [`docs/POSICIONAMENTO-NAO-E.md`](docs/POSICIONAMENTO-NAO-E.md).

### Not a complete CI/CD system

Claude OS does **not** compete with CI/CD pipelines. It does not replace formal stages for build, test, deploy, rollback, environments, artifacts, secrets, promotion, or release automation.

Its job is **before and beside** CI/CD: local pre-validation, evidence preparation, contract checks, drift detection, playbook execution, reducing human/agent error, and delivering **cleaner changes into CI/CD**.

**CI/CD remains the authoritative layer** for build, test, and deployment.

### Not a replacement for GitHub Actions

GitHub Actions remains the **remote, reproducible executor** in a controlled environment. Claude OS should emit commands, profiles, and evidence that Actions can run—but it must **not** replace independent pipeline execution.

Healthy split:

- **Claude OS** defines contracts and commands.
- **GitHub Actions** executes those contracts in CI.

Example: `pwsh ./tools/os-validate.ps1 -Profile strict -Json` can run locally for fast feedback, but **trustworthy green** for release posture should still be **confirmed in CI** (and by human process where required).

### Not a replacement for human review

Claude OS can reduce noise, prepare diffs, validate contracts, surface inconsistencies, and generate evidence. It does **not** replace engineering judgment.

On critical surfaces the system should assume requirements such as: explicit human approval, explicit scope, rollback plan, prior evidence, post validation, and declared residual risk.

The human role is **not** removed—it shifts from reviewing raw chaos to reviewing a **structured change with validation and evidence**.

### Not a SaaS platform

Claude OS stays **local-first**, versionable, and auditable. Turning it into SaaS would shift focus to authentication, tenancy, billing, uptime, and remote control—**not** the core problem this project solves.

Value is in being: portable, local, deterministic, versioned, auditable, vendor-neutral where practical, and **adaptable per project**.

### Not an autonomous production system

Claude OS must **not** execute critical production mutations on its own authority.

Its competence is to **prepare, validate, and contain** actions. For Production, Critical, Incident, Migration, Release, or Destructive work, the posture should be **gated**, for example:

- no human approval → no critical action;
- no evidence → no release;
- no rollback plan → no sensitive change;
- no validation → no “all green” claim.

### Not unsupervised agents on critical paths

Claude OS should **prevent** the failure mode of unbounded autonomy in critical engineering. The system should assume agents may: misread context, over-trust partial validation, change too much at once, treat warnings as success, ignore rollback risk, or introduce documentation drift.

Therefore Claude OS exists to create **technical and procedural containment**.

## Core flow

```text
os-manifest.json
  -> subsystem manifests
  -> validators
  -> health / doctor / validate-all
  -> init-project / update-project
  -> project .claude runtime artifacts
```

## Layers

| Layer | Artefacts | Purpose |
|---|---|---|
| Runtime contract | `VERSION`, `os-manifest.json`, `CHANGELOG.md` | Versioned operational contract |
| Bootstrap contract | `bootstrap-manifest.json`, `init-project.ps1` | Deterministic project scaffold |
| Navigation | `docs-index.json`, `query-docs-index.ps1` | Section-first documentation retrieval |
| Capabilities | `os-capabilities.json`, `capability-manifest.json`, `route-capability.ps1` | Registry (`os.*`) plus intent routes (`route.*`) to skills, playbooks, validators, and evidence |
| Workflow | `workflow-manifest.json`, `workflow-status.ps1` | Progressive artifact-first delivery gates |
| Safety | `templates/checklists/*`, `policies/*` | Human-gated safety and release controls |
| Validation | `tools/verify-*.ps1`, `os-validate-all.ps1`, `quality-gates/*.json` | Drift detection, release validation, manifest-governed quality gates |
| Runtime ops | `os-runtime.ps1`, `os-doctor.ps1`, `os-update-project.ps1` | Unified CLI, diagnostics, managed updates |

## Runtime entrypoint

```powershell
pwsh ./tools/os-runtime.ps1 help
pwsh ./tools/os-runtime.ps1 health
pwsh ./tools/os-runtime.ps1 validate -Strict
pwsh ./tools/os-runtime.ps1 route -Query "security review"
pwsh ./tools/os-runtime.ps1 docs -Query bootstrap
pwsh ./tools/os-runtime.ps1 workflow -Phase verify
```

## Project scaffold

`init-project.ps1` installs managed runtime artifacts into `.claude/`, including docs index, capability registry, workflow manifest, checklists, skills, commands, agents, policies, scripts, and local state seeds.

## Invariants

- Runtime manifests are source of truth.
- Critical scaffold paths are declared in `bootstrap-manifest.json`.
- User/project-owned state is not overwritten by `os-update-project.ps1`.
- Critical surfaces require human approval.
- User-facing output must not expose secrets, PII, stack traces, or raw generated reports.

## Session pipeline (graphify-aligned stance)

[graphify](https://github.com/safishamsi/graphify) documents a staged pipeline (`detect` → … → `export`) and **validate-before-consume** JSON. **Claude OS Runtime** maps that to **prime → absorb → execute → verify → export**: minimal context load (`session-prime`, policies), append-only capture (`session-absorb`), gated execution (`/task-classify`, skills), machine checks (`verify-json-contracts.ps1`, `os-validate-all.ps1`, optional **Invariants** via `templates/invariants/` + `invariant-verify.sh`), then durable handoff (`session-digest`, `decision-log.jsonl`, `session-index.sh`). Orchestration pointers remain in **`os-manifest.json`**; **`init-project.ps1`** materialises the per-project `.claude/` tree.

### Confidence and salience

Optional **Confiança** column on decision rows in `templates/session-state.md` is indexed into `.claude/session-index.json` by `session-index.sh`. Governance JSONL may set `confidence` (enum in `templates/local/decision-log.schema.json`); `decision-append.sh` rejects unknown tokens. **`decision-audit.sh`** keeps CLI `HIGH|MEDIUM|LOW` and maps to `KNOWN|INFERRED|AMBIGUOUS` on write. `salience-score.sh --digest` emits **`session_decision_low_confidence`** (score 73) when the latest indexed session lists `AMBIGUOUS`, `UNKNOWN`, `ASSUMED`, or `DISPUTED` on table decisions — feed Layer 0 in `/session-start`.
