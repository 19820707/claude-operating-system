# /consolidate

**Structural Memory Consolidation** — gera runbooks procedurais em `.claude/runbooks/<slug>.md` a partir de evidência real (`decision-log.jsonl` últimos 180 dias, `git log`, `learning-log.md`, invariantes, `heuristics/operational.md`, estado epistémico).

## Comando

```bash
bash .claude/scripts/consolidate-runbook.sh --module server/auth/index.ts
```

## Saídas

| Ficheiro | Conteúdo |
|----------|-----------|
| `.claude/runbooks/<slug>.md` | Pre-conditions, sequência, learning phases, heurísticas ligadas, failure modes |
| `.claude/runbooks/<slug>.meta.json` | `confidence` (regra: <3 amostras → 0.4 draft; ≥10 commits → cap 0.95), contagens git/decisões |

**Slug:** igual ao usado em `/session-start` (path sem extensão, minúsculas, `/` → `-`).

## Injeção na sessão

```bash
bash .claude/scripts/runbook-inject.sh --module <path>
```

## Limitações

- A **sequência** mistura evidência de decisões com passos canónicos (simulação, `tsc`); validar causalidade antes de tratar como procedimento óptimo.
