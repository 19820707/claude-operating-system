# /session-end

Fecho de sessão operacional: checks automáticos, actualização de estado, commit mínimo.

## Sequência obrigatória

1. **Executar checks** (local, na raiz do repo):
   - `bash .claude/scripts/drift-detect.sh`
   - `bash .claude/scripts/heuristic-ratchet.sh`
   - `bash .claude/scripts/ts-error-budget.sh`
   - `bash .claude/scripts/os-telemetry.sh` (ou `bash .claude/scripts/os-telemetry.sh --report` só para ler métricas sem incrementar `sessions`)
2. **Actualizar** `.claude/session-state.md` com evidência real:
   - **Branch:** `git branch --show-current`
   - **HEAD:** `git log -1 --format="%h %s"`
   - **Fase** e **objectivo** actuais
   - **Estado implementado** (módulos / ficheiros tocados nesta sessão)
   - **WT:** saída de `git status --short`
   - **Decisões**, **riscos**, **checks executados**, **rollback** (comando exacto), **próximos passos mínimos** (acções concretas, não intenções), **fora de scope**
3. **Commit** (se houver alterações relevantes):

```bash
git add .claude/session-state.md .claude/learning-log.md
git commit -m "chore(os): session-end — <objectivo curto>"
```

## Output esperado

```
SESSÃO FECHADA
Branch: <branch>
HEAD: <hash> — <subject>
WT: <N ficheiros> resumo
Drift: <OK | DRIFT — resumo>
Ratchet: <OK | RATCHET — H1/H5/H10>
TS budget: <OK | REGRESSION — N vs baseline>
Telemetry: <score CLEAN|WATCH|ALERT>
session-state.md: actualizado
Commit: <hash ou skipped>
```

## Regras

- Não declarar sessão fechada com **drift** documentado sem explicar na tabela de decisões / riscos por que o git e o `session-state` divergem (ou corrigir o `session-state`).
- Não fechar com **regressão TS** (`ts-error-budget.sh` reporta `RATCHET: REGRESSION`) sem excepção explícita no `learning-log.md` ou sem correcção.
- **Próximos passos:** verbos + artefactos (ex.: «Correr `npx tsc --noEmit` e corrigir 3 erros em `src/foo.ts`»), não «melhorar qualidade».
- **Rollback:** um comando ou sequência copy-paste (ex.: `git revert <hash>` ou `git checkout -- <paths>`), não genéricos.
