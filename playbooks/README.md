# Claude OS playbooks

Operational runbooks for repeatable engineering work. Each playbook is a Markdown file under `playbooks/` and is listed in **`playbook-manifest.json`** with **risk level** and **approval** metadata.

Playbooks whose **`requiresApprovalFor`** includes any of **Release**, **Production**, **Critical**, **Incident**, **Migration**, or **Destructive** must include an **Approval ledger** section pointing at **`docs/APPROVALS.md`**, **`schemas/approval-log.schema.json`**, and the **`append-approval-log`** / **`verify-approval-log`** tools. That ledger is for **human sign-off before steward execution**; it is **not** required for routine local validation.

## Index

| Playbook | Risk | Path |
|----------|------|------|
| Release | critical | [release.md](release.md) |
| Incident | critical | [incident.md](incident.md) |
| Migration | high | [migration.md](migration.md) |
| Bootstrap project | medium | [bootstrap-project.md](bootstrap-project.md) |
| Docs contract audit | medium | [docs-contract-audit.md](docs-contract-audit.md) |
| Autonomous repair (bounded) | medium | [autonomous-repair.md](autonomous-repair.md) |
| Adapter drift repair | high | [adapter-drift-repair.md](adapter-drift-repair.md) |

## Validation

```powershell
pwsh ./tools/verify-playbooks.ps1 -Json
pwsh ./tools/verify-playbooks.ps1 -Strict -Json
```

**`-Strict`** fails if any required section is missing from a playbook body (including **Required approvals**, **Rollback / abort criteria**, **Validation steps**, and **Evidence to collect**, which are mandatory for **high** and **critical** playbooks as part of the full contract).

## Contract

Every playbook body must include these headings (exact titles):

Purpose · Trigger conditions · Required inputs · Risk level · Required approvals · Preflight checks · Execution steps · Validation steps · Rollback / abort criteria · Evidence to collect · Expected outputs · Failure reporting
