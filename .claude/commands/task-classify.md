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

## Forward simulation (obrigatório para Build+ em módulos com score > 60)

```bash
bash .claude/scripts/simulate-change.sh --target <target-file> --change "<descrição>"
```

- Usa `/simulate` para baseline de contrato (`contract-delta.sh --snapshot` quando aplicável), blast radius, invariantes e lacunas epistémicas.
- Resultado **SPLIT** ou **RESOLVE_FIRST** → não avançar para implementação até resolver.

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

## Semantic diff analyzer (contratos, não só linhas)

Compara **`git <base>:ficheiro`** (por defeito `HEAD`) com o **worktree** usando a **TypeScript Compiler API**: superfície exportada (interfaces, tipos, funções/classes exportadas), heurística de **refactor** quando o contrato não muda, e padrões de **semântica de segurança** (ex.: `role === 'admin'` → `roles.includes('admin')`).

```bash
bash .claude/scripts/semantic-diff-analyze.sh --file server/auth/index.ts
bash .claude/scripts/semantic-diff-analyze.sh --base HEAD~1 --file shared/types/session.ts
```

- Saída: blocos `CONTRACT CHANGE DETECTED`, `REFACTOR ANALYSIS`, `SECURITY SEMANTIC CHANGE`; JSON em `.claude/semantic-diff-report.json`.
- Pré-flight opcional: `SEMANTIC_DIFF=1` e `SEMANTIC_DIFF_TARGET=path/to/file.ts` (ver `preflight.sh`).
- **Limitação:** não prova equivalência comportamental formal — combina AST + heurísticas; falhas silenciosas ainda exigem testes.

## Autonomous learning loop (observação → hipótese → política)

Contrasta com **`promote-heuristics.sh`** (promove YAML **já escrito** no `learning-log`): o **`autonomous-learning-loop.sh`** procura **padrões anómalos** em `.claude/session-index.json` + **git** (reverts no módulo), gera **hipóteses testáveis** (`H-AUTO-NNN`) e **rascunhos de política** com confiança — **sem** escrever em `heuristics/operational.md` até revisão humana.

```bash
bash .claude/scripts/autonomous-learning-loop.sh
```

- Saída: blocos `ANOMALY DETECTED`, `HYPOTHESIS H-AUTO-…`, `POLICY SUGGESTION`; JSON em `.claude/learning-loop-report.json`; estado numérico em `.claude/learning-loop-state.json` (template `templates/local/learning-loop-state.json`).
- Pré-flight opcional: `LEARNING_LOOP=1` (ver `preflight.sh`). Depois de validar evidência: copiar regra para `learning-log.md` (YAML) e usar `promote-heuristics.sh --promote` se aplicável.

## Governance I — Decision audit trail (verificabilidade)

Regista a decisão **antes** de actuar (append-only `.claude/decision-log.jsonl`) e audita com políticas **codificáveis** no script (não substitui revisão humana).

```bash
echo '{"id":"D-2026-05-01-001","ts":"2026-05-01T12:00:00Z","session":"main","type":"model_selection","trigger":"server/auth/index.ts","policy_applied":"model-selection.md","evidence":["AUTH"],"alternatives_considered":["Sonnet"],"decision":"Opus","confidence":"HIGH","overridable":false}' | bash .claude/scripts/decision-append.sh
bash .claude/scripts/policy-compliance-audit.sh
```

- Schema: `.claude/decision-log.schema.json`. Auditor: **`[OS-AUDIT]`**, taxa de compliance; se ≥10 decisões auditadas e taxa **&lt;85%** → **DRIFT WARNING**. Pré-flight: `POLICY_AUDIT=1`.

## Governance II — Context topology (grafo + orçamento)

```bash
bash .claude/scripts/context-topology.sh --refresh
bash .claude/scripts/context-topology.sh --inject server/auth/index.ts
bash .claude/scripts/context-topology.sh --budget --for server/auth/index.ts
```

- Persiste `.claude/knowledge-graph.json` (merge de `architecture-graph` + `complexity-map`). Orçamento de tokens é **heurístico** (~chars/4). Pré-flight: `CONTEXT_TOPOLOGY=1` e opcional `CONTEXT_TOPOLOGY_FOR=path`.

## Governance III — Temporal consistency (invariantes com ciclo de vida)

O motor AST verifica **specs** em `.claude/invariants/*.json`. O registo **`.claude/invariants.json`** (template `invariants-registry.seed.json`) guarda metadado de ciclo de vida: `last_verified`, `watched_paths`, `obsolescence_probe`, `genealogy`.

```bash
bash .claude/scripts/invariant-lifecycle.sh
bash .claude/scripts/invariant-lifecycle.sh --for server/billing/stripe.ts
bash .claude/scripts/invariant-lifecycle.sh --apply
```

- **`[OS-INVARIANTS]`**: resumo STALE (commits git após `last_verified` nos paths vigiados), avisos **MAY_BE_OBSOLETE** (reality ≠ spec assumida), linhas **GENEALOGY** (incidente / condição que mudou).
- Relatório máquina: `.claude/invariant-lifecycle-report.json`. **`--apply`** actualiza `status`→`STALE` e `staleness_risk` no registo (não apaga violações nem substitui revisão humana).
- Pré-flight: `INVARIANT_LIFECYCLE=1`; filtro por ficheiro: `INVARIANT_LIFECYCLE_FOR=path/relativo.ts`.

## Governance IV — Multi-agent coordination (leases + intentions)

Ficheiro **`.claude/agent-state.json`**: `leases` (holder, `module`, `blocking` globs, `expires`), `intentions` (opcional `conflict_with` lease ids), `shared_decisions` (`affects` globs, texto da decisão). Protocolo **optimista** — sem servidor central; conflitos e decisões tornam-se observáveis no preflight.

```bash
bash .claude/scripts/coordination-check.sh --paths shared/types/auth.ts,server/auth/index.ts
COORDINATION_PATHS=server/billing COORDINATION_SESSION=my-laptop-01 bash .claude/scripts/coordination-check.sh
COORDINATION_WT=1 bash .claude/scripts/coordination-check.sh
```

- **`[OS-COORDINATION]`**: `CONFLICT DETECTED` se um path cruza lease activo de **outro** holder; aviso **NOTICE** se só há `shared_decisions` aplicáveis; relatório `.claude/coordination-report.json`.
- Pré-flight: `COORDINATION_CHECK=1` (por defeito `COORDINATION_WT=1` para usar o worktree git). Para desligar o scan WT: `COORDINATION_WT=0` e usar `COORDINATION_PATHS=...`.
- Podes fazer commit de `agent-state.json` no repo da equipa para partilha via git (opcional).

## Governance V — Epistemic state (o agente sabe o que não sabe)

Registo **`.claude/epistemic-state.json`**: cada entrada em `facts` tem `status` (`KNOWN`, `INFERRED`, `ASSUMED`, `UNKNOWN`, `DISPUTED`), `confidence`, evidência ou `risk_if_wrong`. Lista `unknown_required` para lacunas bloqueantes.

```bash
bash .claude/scripts/epistemic-check.sh --summary
bash .claude/scripts/epistemic-check.sh --gate --depends "orgId,Session"
bash .claude/scripts/epistemic-check.sh --score-decision D-2026-05-01-001
bash .claude/scripts/epistemic-check.sh --score-all
bash .claude/scripts/epistemic-check.sh --decision-debt
```

- **`[OS-EPISTEMIC]`**: resumo de **assumption debt** (factos `ASSUMED`), `unknown_required`, aviso se dívida alta. **`--gate`** alinha com o plano (`--depends` ou env `EPISTEMIC_PLAN_DEPENDS`) e assinala dependências `ASSUMED`/`DISPUTED` — mensagem forte se `risk_if_wrong` contém HIGH.
- No **decision log**, usa `epistemic_fact_keys: ["substring or fact key", ...]` para permitir **quality score** por decisão (heurística — não substitui revisão humana).
- Pré-flight: `EPISTEMIC_CHECK=1`; gate opcional no mesmo arranque com `EPISTEMIC_PLAN_DEPENDS=...`.
