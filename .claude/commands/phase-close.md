# /phase-close

Executa no fecho de cada fase para capturar aprendizagem e actualizar estado operacional.

## Sequência obrigatória

### 1. Actualizar `.claude/session-state.md`
- branch + HEAD actual
- objectivo da fase fechada
- o que foi implementado (ficheiros + contratos)
- working tree pendente
- decisões tomadas
- riscos abertos ou resolvidos
- checks executados + resultado
- rollback disponível
- próximos passos mínimos
- o que ficou fora de scope

### 2. Append a `.claude/learning-log.md`

Formato obrigatório:
```
### Fase <nome> — <data>
**Objectivo:** ...
**Resultado:** sucesso / falha parcial / bloqueado

**Aprendido:**
- [evidência → padrão]

**Falhou:**
- [o que não funcionou e porquê]

**Passou a regra:** (referência H?)
- H? — [nome da heurística]

**Evitar:**
- [anti-padrão confirmado]

**Próximo passo mínimo:**
- [acção concreta]
```

### 3. Promover heurísticas novas
Se um padrão novo foi confirmado nesta fase:
- adicionar entrada H<n+1> em `memory/heuristics_operational.md`
- referenciar no learning-log com `H<n+1>`

### 4. Confirmar checks mínimos
- `git status` — listar WT pendente
- `git log --oneline -3` — confirmar HEAD
- Testes alvo da fase — PASS/FAIL

### 5. Actualizar índice semântico de sessões
Na raiz do repo do projecto:

```bash
bash .claude/scripts/session-index.sh
```

### 6. Contribuir padrões para o OS (opcional)
Se o clone `claude-operating-system` estiver acessível nesta máquina, sincroniza blocos YAML do `learning-log.md` para o ficheiro central de evidência:

```bash
bash .claude/scripts/cross-project-sync.sh --contribute "/caminho/absoluto/para/claude-operating-system"
```

### 7. Loop de aprendizagem autónoma (opcional)
Se existir `.claude/session-index.json` com histórico de sessões:

```bash
bash .claude/scripts/autonomous-learning-loop.sh
```

- Rever `ANOMALY` / `HYPOTHESIS` / `POLICY SUGGESTION` em consola ou `.claude/learning-loop-report.json`. Só promover regras a `operational.md` após evidência humana (p.ex. YAML no `learning-log.md` + `promote-heuristics.sh`).

### 8. Trilho de decisão (opcional, recomendado para mudanças de alto risco)
Se usas `decision-log.jsonl`, acrescenta **antes** de merges sensíveis uma entrada com `decision-audit.sh` (ou `decision-append.sh` legado) — ver `task-classify` / `.claude/decision-log.schema.json`. Isto separa *raciocínio declarado* de *racionalização post-hoc*.

### 9. Estado epistémico (relatório)
`bash .claude/scripts/epistemic-state.sh --report` — snapshot legível de `facts` e `unknown_required` para fecho de fase.

## Regras

- Distinguir sempre: evidência / inferência / decisão
- Não chamar "regressão" sem evidência
- Não inventar padrões — só promover o que foi observado
- Não fechar fase sem rollback documentado
- Se a fase falhou parcialmente → documentar causa exacta, não simplificar
