# /claim-module

Adquire lease de escrita num módulo antes de trabalho **WRITE** concorrente.

## Sequência

1. `bash .claude/scripts/agent-coordinator.sh --expire`
2. `bash .claude/scripts/agent-coordinator.sh --check <module-path>`
3. Se o passo anterior reportar **CONFLICT**, apresentar ao utilizador e não prosseguir sem coordenação explícita.
4. `bash .claude/scripts/agent-coordinator.sh --acquire <module> --type WRITE --intent "<tarefa em uma frase>" --duration 120`
5. Registar o `LEASE-ID` devolvido em `.claude/session-state.md` (secção de trabalho activo / WT).

## Regras

- Usar antes de qualquer trabalho em módulos **críticos partilhados** (auth, billing, tipos partilhados).
- `intent` pode conter espaços entre `--intent` e `--duration`.
