<!-- Engineering OS — ../../CLAUDE.md + ../../.agents/OPERATING_CONTRACT.md -->
<!-- Invariant: classify before implement; mode and model must be explicit before any edit. -->
<!-- Never: assume Fast mode for work touching critical surfaces (auth, billing, migrations). -->
<!-- Fail closed: uncertain classification -> assume most conservative mode. -->

# /task-classify

Classify a task before implementing it. Determines Mode, Model, blast radius, and approval requirement.
**After classifying, dispatch work to the correct model via the Agent tool — never execute in a higher-cost model than needed.**

## Classification matrix

| Surface | Mode | Model | Agent dispatch |
|---------|------|-------|---------------|
| discovery, grep, file reads | Explore | **Haiku** | `Agent(model:"haiku")` |
| docs, templates, OS files | Fast | Sonnet | main session or `Agent(model:"sonnet")` |
| tests, refactor, wiring | Build | Sonnet | `Agent(model:"sonnet")` |
| boundaries, central flows | Review -> Build | Sonnet | `Agent(model:"sonnet")` |
| auth, billing, SW, CSRF, OIDC, headers | Critical | **Opus** | `Agent(model:"opus")` — mandatory |
| migrations (non-additive) | Migration | **Opus** | `Agent(model:"opus")` — mandatory |
| pre-deploy, runbooks | Production-safe | **Opus** | `Agent(model:"opus")` — mandatory |

## Dispatch rules

1. **Haiku** — any task that is pure reading, grep, file listing, context prep, status checks. Never edits.
2. **Sonnet** — scoped implementation where the design is already decided. No critical surfaces.
3. **Opus** — any task that touches auth, CSRF, session, cookies, billing, SW/cache, security headers, migrations, entitlement, or requires multi-constraint architectural reasoning.
4. **Never run Opus on work Sonnet can do** — saves tokens, preserves Opus budget for decisions that require it.
5. **Never run Sonnet on Opus-mandatory surfaces** — insufficient reasoning depth for invariant detection.
6. **Main session model** handles only coordination, classification, and orchestration between subagents.

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
Model: Haiku | Sonnet | Opus
Dispatch: Agent(model:"haiku"|"sonnet"|"opus") | main session
Blast radius: ...
Human approval required: yes | no
Rollback: ...
Regression test: ...
```

## Complexity Check (antes de qualquer edição)

Na raiz do repo, para o ficheiro principal que vais alterar:

```bash
bash .claude/scripts/module-complexity.sh caminho/relativo/ao/ficheiro.ts
```

- Interpreta o bloco **`[OS-MODULE-COMPLEXITY]`**: score **CRITICAL** ou **ELEVATED** → **Opus obrigatório** independentemente do tipo de tarefa.
- Resultados agregados de `bash .claude/scripts/module-complexity.sh --scan` ficam em `.claude/complexity-map.json` (requer `.claude/risk-surfaces.json` do `risk-surface-scan.sh`).
