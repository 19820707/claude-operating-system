# /consolidate-runbook

**Structural Memory Consolidation** — transforma evidência episódica (`decision-log.jsonl`), semântica (`learning-log.md`), invariantes e factos epistémicos num **runbook procedural** específico do repositório (memória de *como* executar mudanças neste módulo, não só *o que* aconteceu).

## Quando usar

- Após uma série de alterações bem-sucedidas num mesmo módulo crítico.
- Periodicamente em superfícies de alto churn (auth, billing, etc.).
- Antes de delegar trabalho noutro agente sobre o mesmo caminho.

## Comando

```bash
bash .claude/scripts/consolidate-runbook.sh --module server/auth/index.ts
```

## Saídas

| Ficheiro | Conteúdo |
|----------|-----------|
| `.claude/runbooks/<slug>.md` | Runbook markdown (pre-conditions, sequência derivada de decisões, failure modes, rollback) |
| `.claude/runbooks/<slug>.meta.json` | `confidence` heurístico, contagens, lista de invariantes cruzados |

**Slug:** caminho relativo sem extensão `.ts`/`.tsx`/…, minúsculas, separadores não alfanuméricos e `/` → `-` (ex.: `server/auth/index.ts` → `server-auth-index`).

## Limitações (v1)

- “Sucesso” é **heurística** (ausência de palavras como revert/incident na linha de decisão); não substitui revisão humana.
- A sequência lista decisões recentes como *evidência*; o agente deve validar causalidade antes de tratar como procedimento óptimo.

## Relação com `/session-start`

O `/session-start` deve **detectar** `.claude/runbooks/<slug>.md` para o módulo alvo e **injetar o runbook na CAMADA 1** (ver `session-start.md`).
