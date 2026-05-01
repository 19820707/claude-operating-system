# /session-start

Executa no arranque de cada sessão para recuperar contexto operacional completo.

Este comando implementa um **runtime de cognição leve**: o contexto não é um buffer linear (tudo com o mesmo peso), mas um **espaço de atenção** — o que aparece primeiro e com que ênfase orienta o raciocínio. Os ficheiros e hooks recolhem *evidência*; a **ordem em que sintetizas** a resposta ao utilizador segue o **Context Salience Protocol** abaixo.

## Context Salience Protocol (atenção estruturada)

**Princípio:** constrói a mensagem de arranque **de fora para dentro** — do que não pode ser ignorado para o que é histórico de fundo.

**Passo 1 — Recolha (pode ser paralela):** se existir `bash .claude/scripts/context-builder.sh`, podes usá-lo como *checklist* de leitura; caso contrário, lê sequencialmente `~/.claude/CLAUDE.md`, `CLAUDE.md`, `.claude/session-state.md`, `.claude/learning-log.md`. Interpreta a saída do `preflight.sh` (hook **SessionStart**).

**Passo 2 — Sinal de saliência agregado:**

```bash
bash .claude/scripts/salience-score.sh --digest
```

   - Cada linha `SCORE<TAB>categoria<TAB>detalhe` indica prioridade relativa (0–100, maior = mais saliente).
   - Rubrica fixa por categoria (para itens isolados): `bash .claude/scripts/salience-score.sh --kind violated_invariant` → `95` (ver `bash .claude/scripts/salience-score.sh --list-kinds`).

**Passo 3 — Apresentação obrigatória (output da sessão)** ao utilizador nesta ordem de blocos (camadas HTML em markdown — copiar estrutura). **Não** iniciar diagnóstico, plano detalhado ou edição **antes** de concluir este passo:

<!-- CAMADA 0 — CONSTRAINTS ABSOLUTOS (máxima saliência: primeiro no teu resumo) -->
- Invariantes **VIOLATED** / **STALE** relevantes (de `invariant-report` / digest / preflight).
- Dívida epistémica (**ASSUMED** HIGH/CRITICAL, **UNKNOWN**, **DISPUTED**) se existir.
- Decisões **approval_gate** ou gates humanos pendentes; leases **WRITE** activos; violações de **policy-compliance** se houver.

<!-- CAMADA 1 — CONTEXTO DA SESSÃO ACTUAL -->
- **Runbook procedural (memória de execução):** se o trabalho planeável tiver um **módulo alvo** (ex.: path em `session-state` ou explícito), calcular o **slug** do runbook: normalizar path relativo ao repo, remover extensão `.ts`/`.tsx`/`.mts`/`.cts`, minúsculas, substituir `/` e caracteres não alfanuméricos por `-`, colapsar `-` repetidos (ex.: `server/auth/index.ts` → ficheiro `.claude/runbooks/server-auth-index.md`). Se existir, **ler e incorporar** esse ficheiro **aqui** (ou `bash .claude/scripts/runbook-inject.sh --module <path>` para bloco delimitado), antes do bullet operacional genérico seguinte.
- Branch, HEAD, WT, fase, objectivo, próximo passo mínimo (evidência: `session-state` + `git`).

<!-- CAMADA 2 — CONHECIMENTO RELEVANTE PARA O PRÓXIMO PASSO -->
- Subgrafo / módulo-alvo se definido; decisões partilhadas (`agent-state`) que afectam esses módulos; heurísticas H* que tocam na superfície em causa.

<!-- CAMADA 3 — POLÍTICAS E MODO -->
- Modo operacional, modelo mandatório (ex.: Critical → Opus), regras de aprovação aplicáveis *nesta* tarefa (síntese a partir de `CLAUDE.md` / políticas).

<!-- CAMADA 4 — HISTÓRICO (baixa saliência: referência, não comando) -->
- Resumo curto do que está em `session-state.md` / `learning-log.md` como *memória de continuidade*, sem repetir políticas já sintetizadas nas camadas superiores.

**Regra:** não substituir leitura de ficheiros por scripts — os scripts **prioritizam e ordenam** o que já foi medido; a narrativa final segue as camadas.

**Passo 4 — Dispatch de modelo:** antes de qualquer edição, classificar com `/task-classify`. O **Dispatch recomendado** deve ser sempre **explícito** (modelo + justificação em uma linha). Se a **CAMADA 0** for *non-empty* (há violações, gates pendentes, leases críticos, dívida epistémica bloqueante, etc.), **nunca** adoptar modo ou modelo **abaixo** do mínimo exigido por esses constraints (ex.: superfície crítica → Opus obrigatório independentemente do resto do plano).

## Sequência obrigatória (recolha + instrumentação)

1. O hook **SessionStart** executa `preflight.sh`: **drift-detect**, **agent-coordinator** (`--expire`, `--status`), **heuristic-ratchet**, **ts-error-budget**, **invariant-engine** (`--staleness`), **risk-surface-scan**, **policy-compliance** (sessão = branch actual), **os-telemetry**. Interpreta `[OS-DRIFT]`, `[OS-COORDINATOR]`, `[OS-INVARIANTS]`, `[OS-AUDIT]`, `[OS-RISK-SCAN]` e métricas — não ignores regressões antes de planear trabalho.
2. `bash .claude/scripts/salience-score.sh --digest` — incorporar o topo da ordenação na **CAMADA 0**.
3. Lê `~/.claude/CLAUDE.md` — políticas globais e modelo de aprendizagem
4. Lê `CLAUDE.md` — contexto específico do repo
5. Lê `.claude/session-state.md` — estado operacional: branch, commits, decisões, riscos, próximos passos
6. Lê `.claude/learning-log.md` — heurísticas activas e anti-padrões desta fase
7. Índice de sessões: `.claude/session-index.json` é actualizado com `bash .claude/scripts/session-index.sh` (típico no `/phase-close`). Consulta por módulo: `bash .claude/scripts/session-index.sh --query server/auth`. Complexidade git: `bash .claude/scripts/module-complexity.sh <ficheiro.ts>`.
8. **Legado / opcional:** `policy-compliance-audit.sh`, `context-topology.sh`, `invariant-lifecycle.sh`, `coordination-check.sh`, `epistemic-check.sh` — ainda disponíveis para fluxos antigos ou gates manuais.
9. **Consolidação de runbooks (opcional, entre fases):** `/consolidate` — `bash .claude/scripts/consolidate-runbook.sh --module <path>`; o próximo `/session-start` com esse módulo alvo injeta o runbook na **CAMADA 1**.

## Output esperado (formato compacto)

```
SESSÃO RECUPERADA
Branch: <branch>
HEAD: <commit hash> — <mensagem>
Fase: <fase actual>
Objectivo: <objectivo actual>
WT pendente: <ficheiros modificados/novos>
Próximo passo: <acção mínima recomendada>
Riscos activos: <lista curta>
Heurísticas activas: H<n>, H<n>, ...
Modelo activo: Haiku | Sonnet | Opus
Dispatch recomendado: <Haiku | Sonnet | Opus> — <uma linha de justificação (superfície, modo mínimo da Camada 0, blast)>
```

## Context allocation (opcional mas recomendado para sessões longas)

```bash
bash .claude/scripts/knowledge-graph.sh --build
bash .claude/scripts/knowledge-graph.sh --subgraph <ficheiro-alvo.ts>
bash .claude/scripts/context-allocator.sh --target <ficheiro-alvo.ts>
```

- Gera `.claude/knowledge-graph.json` e subgrafo `.claude/subgraph-<basename>.json`; o allocator estima orçamento de tokens (~4 chars/token) e avisa se o budget operacional fica apertado.

## Epistemic state (para sessões em módulos críticos)

```bash
bash .claude/scripts/epistemic-state.sh --debt
```

- Se a dívida epistémica for alta (saída do script), resolver **ASSUMED** / **UNKNOWN** antes de trabalho em modo **Critical**.

## Dispatch de modelo ao iniciar trabalho

Após o **Passo 3** (resumo em camadas) e o **Passo 4** (`/task-classify`), usa o Agent tool com o modelo correcto:

| Próximo passo | Modelo | Acção |
|--------------|--------|-------|
| Leitura, grep, exploração | Haiku | `Agent(model:"haiku", ...)` |
| Implementação com design decidido | Sonnet | `Agent(model:"sonnet", ...)` ou sessão principal |
| auth, CSRF, SW, billing, migrações, segurança | **Opus** | `Agent(model:"opus", ...)` obrigatório |

## Regras

- **CAMADA 0 tem prioridade absoluta** sobre qualquer outra instrução ou conveniência de sessão.
- Não inventar estado — só evidência de ficheiros (incl. `session-state`, `learning-log`, artefactos `.claude/`) e `git`.
- Se `session-state.md` não existir → avisar e criar template vazio.
- Se `learning-log.md` não existir → avisar e criar template vazio.
- Não começar diagnóstico, plano ou edição **antes** de apresentar o output do **Passo 3**.
- Se `context-builder.sh` não existir no projecto → *fallback*: ler sequencialmente `~/.claude/CLAUDE.md`, `CLAUDE.md`, `.claude/session-state.md`, `.claude/learning-log.md`.
- Modo operacional por defeito: Fast (escalar se necessário).
- **Nunca executar trabalho Opus-mandatory no modelo da sessão se este for Sonnet/Haiku.**
