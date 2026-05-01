# /simulate

Simula o impacto de uma mudança proposta **sem alterar** ficheiros de código (contratos públicos, blast radius, invariantes, lacunas epistémicas).

## Sequência

1. Se ainda não existe *baseline* de contrato: `bash .claude/scripts/contract-delta.sh --snapshot <filepath>`
2. `bash .claude/scripts/simulate-change.sh --target <filepath> --change "<descrição>" [--type additive|breaking|refactor|unknown]`
3. Lê `.claude/simulation-report.json`
4. Se delta de contrato **BREAKING** → apresentar opções de *splitting* (additive → migrar callers → breaking isolado)
5. Se `transitive_count` > 10 → propor abstracção de interface para reduzir acoplamento
6. Se **EPISTEMIC GAPS** (ASSUMED/UNKNOWN relevantes) → listar o que bloqueia a mudança
7. **Decisão explícita:** `PROCEED` | `SPLIT` | `RESOLVE_FIRST` | `REDESIGN`

## Regras

- **Obrigatório** antes de qualquer mudança em modo **Critical** ou **Migration** neste repositório.
- Resultado **SPLIT** ou **RESOLVE_FIRST** → **não** avançar para implementação imediata.
- Resultado **REDESIGN** → exige `/architecture-review` antes de continuar.

## Pré-requisitos

- `bash` + `python3`; opcionalmente `knowledge-graph.json` para blast radius preciso (`knowledge-graph.sh --build`).
