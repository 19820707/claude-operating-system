# /session-start

Executa no arranque de cada sessão para recuperar contexto operacional completo.

## Sequência obrigatória

1. Lê `~/.claude/CLAUDE.md` — políticas globais e modelo de aprendizagem
2. Lê `CLAUDE.md` — contexto específico do repo
3. Lê `.claude/session-state.md` — estado operacional: branch, commits, decisões, riscos, próximos passos
4. Lê `.claude/learning-log.md` — heurísticas activas e anti-padrões desta fase
5. O hook **SessionStart** executa `preflight.sh`, que corre **drift-detect**, **heuristic-ratchet**, **ts-error-budget**, **risk-surface-scan** e **os-telemetry**. Interpreta `[OS-DRIFT]`, `[OS-HEURISTIC-RATCHET]`, `[OS-TS-BUDGET]`, `[OS-RISK-SCAN]` e o resumo de métricas — não ignores regressões antes de planear trabalho.
6. Índice de sessões: `.claude/session-index.json` é actualizado com `bash .claude/scripts/session-index.sh` (típico no `/phase-close`). Consulta por módulo: `bash .claude/scripts/session-index.sh --query server/auth`. Complexidade git: `bash .claude/scripts/module-complexity.sh <ficheiro.ts>`.

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
