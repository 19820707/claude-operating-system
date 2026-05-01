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

## Complexity check (antes de qualquer edição)

Na raiz do repo, para o ficheiro principal que vais alterar:

```bash
bash .claude/scripts/module-complexity.sh caminho/relativo/ao/ficheiro.ts
```

- Interpreta o bloco **`[OS-MODULE-COMPLEXITY]`** conforme o score.
- Resultado **CRITICAL** ou **ELEVATED** → **Opus obrigatório** independentemente do tipo de tarefa.
- Resultado em `.claude/complexity-map.json` após `bash .claude/scripts/module-complexity.sh --scan` (requer `.claude/risk-surfaces.json` do `risk-surface-scan.sh`).

## Living architecture graph (blast radius transitivo)

O grafo em `.claude/architecture-graph.json` é **extraído de imports estáticos** (não é só texto do `CLAUDE.md`). Antes de editar um ficheiro sob `server/`, `client/`, `shared/` ou `src/`:

```bash
bash .claude/scripts/living-arch-graph.sh --blast-radius caminho/relativo/ao/ficheiro.ts
```

- **Dependentes directos / transitivos** = módulos que importam a cadeia à volta do ficheiro (propagação reversa do grafo).
- Se a recomendação indicar **Review / Opus** → tratar como classificação conservadora mesmo que a tarefa pareça pequena.
- Ajustar fronteiras em `.claude/architecture-boundaries.json` (copiado do template em init) quando a stack tiver camadas diferentes.

## Invariant verification (AST, não grep)

Especificações JSON em `.claude/invariants/*.json` — verificação com **TypeScript Compiler API** (motor empacotado em `.claude/invariant-engine/invariant-engine.cjs`).

```bash
bash .claude/scripts/invariant-verify.sh
```

- Saída humana com prefixo **`[OS-INVARIANT]`**; relatório máquina em `.claude/invariant-report.json`.
- Tipos de `check` suportados: `pattern_count` (contagens com posições via `SourceFile`), `fail_closed_switch` (AST `SwitchStatement` + `default`), `ast_pattern` com `ast_query` referindo `SwitchStatement` (mapeado para o mesmo verificador), `sensitive_logger` (chamadas a sinks + argumentos), `missing_pattern` (ficheiros sem token obrigatório — WARN).
- Para correr no arranque da sessão: `INVARIANT_VERIFY=1` (ver `preflight.sh`). **CRITICAL** `FAIL` deve bloquear merge / exigir Opus + revisão humana.

## Probabilistic risk model (calibração histórica)

Substitui ou complementa risco **puramente categórico** com estimativas a partir do **git (180d)** e, quando existir, **`.claude/architecture-graph.json`** (blast transitivo por módulo) + **`coverage/coverage-summary.json`** (P(regression|coverage)).

```bash
bash .claude/scripts/probabilistic-risk-model.sh --file caminho/relativo/ao/ficheiro.ts
# ou: --module server/auth
# opcional: --change-lines N
```

- Interpreta **`[OS-RISK-MODEL]`**: `composite` alto ou `P(incident)` elevado → **Opus** / modo **Review** como na matriz, mesmo que a tarefa pareça pequena.
- Resultado em `.claude/risk-model.json`. Pré-flight opcional: `RISK_MODEL=1` e `RISK_MODEL_TARGET=path/to/file.ts` (ver `preflight.sh`).
- **Nota:** P(incident) usa sinais de mensagem (`hotfix`, `incident`, `revert`, …) como *proxy* — não substitui post-mortems nem etiquetas humanas de incidente.
