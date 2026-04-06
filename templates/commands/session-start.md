# /session-start

Executa no arranque de cada sessão para recuperar contexto operacional completo.

## Sequência obrigatória

1. Lê `~/.claude/CLAUDE.md` — políticas globais e modelo de aprendizagem
2. Lê `CLAUDE.md` — contexto específico do repo
3. Lê `.claude/session-state.md` — estado operacional: branch, commits, decisões, riscos, próximos passos
4. Lê `.claude/learning-log.md` — heurísticas activas e anti-padrões desta fase

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
```

## Regras

- Não inventar estado — só evidência de session-state.md e git
- Se session-state.md não existir → avisar e criar template vazio
- Se learning-log.md não existir → avisar e criar template vazio
- Não começar diagnóstico, plano ou edição antes de apresentar o resumo
- Modo operacional por defeito: Fast (escalar se necessário)
