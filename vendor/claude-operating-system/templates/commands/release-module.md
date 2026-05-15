# /release-module

Liberta lease e regista decisões arquitecturais partilhadas.

## Sequência

1. `bash .claude/scripts/agent-coordinator.sh --release <LEASE-ID>`
2. Se houve decisão arquitectural durante o lease:
   `bash .claude/scripts/agent-coordinator.sh --decide "<texto>" --affects "<mod1,mod2>" --session "$(git branch --show-current)-$(date +%H)"`
3. Verificar decisões pendentes: `bash .claude/scripts/agent-coordinator.sh --status`

## Regras

- `--decide` aceita texto com espaços entre `--decide` e `--affects`.
- `acknowledge` para decisões alheias: ver saída de `--check` para o comando exacto `--acknowledge`.
