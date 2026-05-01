# /audit-session

Audita compliance de políticas para a sessão actual ou histórico.

## Sequência

1. `bash .claude/scripts/policy-compliance.sh --session "$(git branch --show-current)"`
2. Lê `.claude/compliance-report.json`
3. Para cada entrada **NON-COMPLIANT** no relatório: apresenta `id`, tipo, política violada (`reason`) e impacto potencial (inferido do `trigger` no `decision-log.jsonl` se necessário).
4. Taxa de compliance:
   - Se **&lt; 85%**: propõe rever se as políticas estão demasiado restritivas ou se a disciplina operacional falhou.
   - Se **≥ 85%**: confirma que a disciplina operacional está alinhada com as expectativas.

## Output esperado

```
AUDIT SESSION
Branch: <branch>
Compliance: <rate>% (<compliant>/<total>)
Violations: <n>
NON-COMPLIANT: <resumo por id>
```

## Regras

- Não usar para **punir** — usar para **calibrar** políticas e fluxo de decisão.
- Se `decision-log.jsonl` estiver vazio, o script reporta skip — isso é um sinal de maturidade do trilho de auditoria, não de falha moral.
