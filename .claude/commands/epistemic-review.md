# /epistemic-review

Audita a qualidade epistémica das decisões e factos activos.

## Sequência

1. `bash .claude/scripts/epistemic-state.sh --debt`
2. `bash .claude/scripts/epistemic-state.sh --verify-assumed`
3. `bash .claude/scripts/epistemic-state.sh --report`
4. Para cada **ASSUMED** com `risk_if_wrong` **HIGH** ou **CRITICAL**: mostrar `verification_command` (se existir) e pedir confirmação humana antes de promover a **KNOWN**.
5. Para cada **UNKNOWN** em `unknown_required`: avaliar se bloqueia o plano actual (auth, billing, etc.).
6. Para decisões com `epistemic_quality` &lt; 0.60 (ver `.claude/epistemic-report.json` após `--score --decision D-…`): recomendar re-avaliação antes de merge.

## Output esperado

```
EPISTEMIC REVIEW
Debt score: <n>
High-risk assumptions: <lista>
Unknowns: <lista>
```

## Regras

- Antes de trabalho em modo **Critical** num módulo sensível: executar `/epistemic-review` quando existirem factos **ASSUMED** ou **DISPUTED** no registo.
