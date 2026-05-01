# /session-start

Executa no arranque de cada sessão para recuperar contexto operacional completo.

## Sequência obrigatória

1. Lê `~/.claude/CLAUDE.md` — políticas globais e modelo de aprendizagem
2. Lê `CLAUDE.md` — contexto específico do repo
3. Lê `.claude/session-state.md` — estado operacional: branch, commits, decisões, riscos, próximos passos
4. Lê `.claude/learning-log.md` — heurísticas activas e anti-padrões desta fase
5. O hook **SessionStart** executa `preflight.sh`: **drift-detect**, **agent-coordinator** (`--expire`, `--status`), **heuristic-ratchet**, **ts-error-budget**, **invariant-engine** (`--staleness`), **risk-surface-scan**, **policy-compliance** (sessão = branch actual), **os-telemetry**. Interpreta `[OS-DRIFT]`, `[OS-COORDINATOR]`, `[OS-INVARIANTS]`, `[OS-AUDIT]`, `[OS-RISK-SCAN]` e métricas — não ignores regressões antes de planear trabalho.
6. Índice de sessões: `.claude/session-index.json` é actualizado com `bash .claude/scripts/session-index.sh` (típico no `/phase-close`). Consulta por módulo: `bash .claude/scripts/session-index.sh --query server/auth`. Complexidade git: `bash .claude/scripts/module-complexity.sh <ficheiro.ts>`.
7. **Legado / opcional:** `policy-compliance-audit.sh`, `context-topology.sh`, `invariant-lifecycle.sh`, `coordination-check.sh`, `epistemic-check.sh` — ainda disponíveis para fluxos antigos ou gates manuais.

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
Dispatch recomendado: <se o próximo passo toca superfície crítica → Opus; se é leitura → Haiku>
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

Após o resumo, antes de qualquer edição, classifica o próximo passo com `/task-classify` e usa o Agent tool com o modelo correcto:

| Próximo passo | Modelo | Acção |
|--------------|--------|-------|
| Leitura, grep, exploração | Haiku | `Agent(model:"haiku", ...)` |
| Implementação com design decidido | Sonnet | `Agent(model:"sonnet", ...)` ou sessão principal |
| auth, CSRF, SW, billing, migrações, segurança | **Opus** | `Agent(model:"opus", ...)` obrigatório |

## Regras

- Não inventar estado — só evidência de session-state.md e git
- Se session-state.md não existir → avisar e criar template vazio
- Se learning-log.md não existir → avisar e criar template vazio
- Não começar diagnóstico, plano ou edição antes de apresentar o resumo
- Modo operacional por defeito: Fast (escalar se necessário)
- **Nunca executar trabalho Opus-mandatory no modelo da sessão se este for Sonnet/Haiku**
