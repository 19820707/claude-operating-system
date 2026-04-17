<!-- Engineering OS — ../../CLAUDE.md + ../../.agents/OPERATING_CONTRACT.md -->
<!-- Invariant: classify before implement; mode and model must be explicit before any edit. -->
<!-- Never: assume Fast mode for work touching critical surfaces (auth, billing, migrations). -->
<!-- Fail closed: uncertain classification -> assume most conservative mode. -->

# /task-classify

Classify a task before implementing it. Determines Mode, Model, blast radius, and approval requirement.

## Classification matrix

| Surface | Mode | Model | Approval |
|---------|------|-------|----------|
| docs, templates, OS files | Fast | Sonnet | auto-accept permitted |
| tests, refactor, wiring | Build | Sonnet | manual or semi |
| boundaries, central flows | Review -> Build | Sonnet | manual |
| auth, billing, SW, CSRF, OIDC, headers | Critical | **Opus mandatory** | manual always |
| migrations (non-additive) | Migration | **Opus mandatory** | manual + staging |
| pre-deploy, runbooks | Production-safe | **Opus mandatory** | manual + checklist |

## Classification tags (OPERATING_CONTRACT.md)

| Tag | Scope |
|-----|-------|
| A | UI/frontend -- pages, components, hooks |
| B | Auth/Identity -- login, session, cookies, OIDC, RBAC, CSRF |
| C | Service Worker / cache / offline |
| D | Backend/API -- routes, middleware, storage, payments, headers |
| E | Infra/CI/gates |

## Output before any edit

```
Task: (one line description)
Classification (A-E): ...
Mode: Fast | Build | Review | Critical | Migration | Production-safe
Model: Haiku | Sonnet | Opus (mandatory if B/C/D touching runtime)
Blast radius: ...
Human approval required: yes | no
Rollback: ...
Regression test: ...
```
