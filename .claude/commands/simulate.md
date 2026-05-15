# /simulate

Simula o impacto de uma mudança proposta **sem alterar** ficheiros de código (contratos públicos, blast radius, invariantes, lacunas epistémicas).

**Uso:** `/simulate <filepath> [descrição da mudança]`

## Sequência

1. `bash .claude/scripts/contract-delta.sh --snapshot <filepath>` — apenas se ainda **não** existir `.claude/contracts/<slug>.json` para esse alvo (o `simulate-change.sh` faz compare vs baseline quando o snapshot já existe).
2. `bash .claude/scripts/simulate-change.sh --target <filepath> --change "<descrição>"`
3. Lê `.claude/simulation-report.json`
4. Se **BREAKING** no contract delta → apresentar opções de *splitting* da mudança
5. Se **blast_radius** `transitive_count` > 10 → propor abstracção de interface para reduzir coupling
6. Se **ASSUMPTION / EPISTEMIC GAPS** → listar assumptions e **UNKNOWN** que bloqueiam esta mudança
7. **Decisão explícita:** `PROCEED` | `SPLIT` | `RESOLVE_FIRST` | `REDESIGN`

## Regras

- **Obrigatório** antes de qualquer mudança em modo **Critical** ou **Migration** neste repositório.
- Resultado **SPLIT** ou **RESOLVE_FIRST** → **não** avançar para implementação imediata.
- Resultado **REDESIGN** → exige `/architecture-review` antes de continuar.

## Pré-requisitos

- `bash` + `python3`; opcionalmente `knowledge-graph.json` para blast radius preciso (`knowledge-graph.sh --build`).
