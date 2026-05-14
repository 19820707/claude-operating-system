# /verify-invariants

Verifica invariantes com ciclo de vida e relatório máquina.

## Sequência

1. `bash .claude/scripts/invariant-engine.sh --staleness`
2. `bash .claude/scripts/invariant-engine.sh --verify-all`
3. Lê `.claude/invariant-report.json`
4. Para cada **VIOLATED**: localização em `details[].detail` + remediação sugerida (corrigir padrão, mover dependência, actualizar testes).
5. Para cada **STALE**: re-verificar antes de editar o módulo afectado (re-correr `--verify-all` após leitura do código).
6. Para pistas de **OBSOLETE** (modo `--lifecycle`): `bash .claude/scripts/invariant-engine.sh --lifecycle` e actualizar `templates/invariants/core.json` / `.claude/invariants.json` após revisão humana.

## Output esperado

```
INVARIANTS
VERIFIED: N  STALE: S  VIOLATED: V  UNKNOWN: U
CRITICAL violations: <lista ou none>
```

## Regras

- **VIOLATED** com `violation_severity: CRITICAL` bloqueia trabalho em modo **Critical** até haver plano de correcção e evidência no `session-state.md`.
- O motor é heurístico (grep / grafo); não substitui testes nem revisão Opus em superfícies sensíveis.
