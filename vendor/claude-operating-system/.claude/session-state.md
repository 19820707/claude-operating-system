# Session State — claude-operating-system

> Handoff técnico persistente entre sessões.  
> Actualizar no fecho de cada sessão. **Sem** segredos, tokens ou credenciais.

---

## Identificação

| Campo | Valor |
|-------|-------|
| Branch | `main` |
| HEAD | `4d9fc48` |
| Data da última actualização | 2026-05-03 (sessão: L4/L6/L7 docs + registo de componente) |

---

## Fase actual

**Documentação de governação** — contrato operacional (L4), matriz de confirmação (L7), estado de sessão (L6). Sem novos scripts, sem schemas novos, sem gates enfraquecidos.

---

## Objectivo actual

Reduzir microconfirmações em operações **read-only** (incl. superfícies críticas como auth/RLS/migrations/CI/production-adjacent **só leitura**), mantendo aprovação humana em mutações de risco e alinhamento com `policies/autonomy-policy.json`.

---

## Estado implementado

| Módulo/Ficheiro | Estado |
|----------------|--------|
| `.agent/operating-contract.md` | **Novo** — L4 explícito (read-only autónomo em qualquer superfície; writes conforme matriz). |
| `policies/auto-approve-matrix.md` | **Novo** — matriz L7 (nunca / autónomo se reversível+validado / sempre humano) com exemplos. |
| `policies/autonomy.md` | **Actualizado** — referência à matriz L7 em Related. |
| `component-manifest.json` | **Actualizado** — mapeamento `policy:policies/auto-approve-matrix.md` (exigido por `verify-components`). |

---

## Working tree (não commitado)

| Ficheiro | Estado | Notas |
|----------|--------|-------|
| `tools/os-runtime.ps1` | Modificado (pré-existente neste clone) | Fora do âmbito directo desta entrega L4/L6/L7; rever antes de commit conjunto. |
| `.agent/operating-contract.md` | Novo | Contrato canónico no repo. |
| `policies/auto-approve-matrix.md` | Novo | |
| `component-manifest.json` | Modificado | Cobertura de componentes. |
| `policies/autonomy.md` | Modificado | Link L7. |
| `.claude/session-state.md` | Novo | Este ficheiro. |

---

## Decisões tomadas

| ID | Decisão | Ficheiros | Commit | Risco associado | Confiança |
|----|---------|-----------|--------|-----------------|-----------|
| D-L4 | Contrato L4 no repo em `.agent/operating-contract.md` (não só template) para agentes lerem a mesma verdade que o INDEX aponta. | `.agent/operating-contract.md` | pendente | Baixo — só prosa; não altera executáveis. | KNOWN |
| D-L7 | Matriz em `policies/` para conviver com `autonomy.md` / JSON. | `policies/auto-approve-matrix.md` | pendente | Baixo — interpretação humana+agente; JSON continua fonte máquina para autopilot. | KNOWN |
| D-COMP | Registar política nova no `component-manifest.json` para `verify-components` passar. | `component-manifest.json` | pendente | Baixo — metadata. | KNOWN |

---

## Riscos abertos

| Risco | Severidade |
|-------|------------|
| `tools/os-runtime.ps1` modificado sem revisão nesta sessão | Média — pode misturar-se com commit de docs. |
| Matriz L7 é normativa; desalinhamento futuro com `autonomy-policy.json` se só um for actualizado | Baixa — mitigar com reviews e `verify-autonomy-policy`. |

---

## Checks executados

| Check | Resultado |
|-------|-----------|
| `pwsh ./tools/os-validate.ps1 -Profile quick -Json` | **ok** (após entrada `policies/auto-approve-matrix.md` no `component-manifest.json`). |
| `verify-components` (isolado) | **ok** após mapeamento da nova política. |

---

## Rollback disponível

```powershell
# Descartar só esta entrega (ficheiros novos + manifest + autonomy link)
git checkout -- component-manifest.json policies/autonomy.md
Remove-Item -Force -Recurse .agent
Remove-Item -Force policies/auto-approve-matrix.md, .claude/session-state.md
```

(Rever `tools/os-runtime.ps1` à parte se não fizer parte desta entrega.)

---

## Próximos passos mínimos

1. Rever `git diff` (incl. `tools/os-runtime.ps1` se não for intencional).  
2. `pwsh ./tools/os-validate.ps1 -Profile quick -Json` antes de commit (já **ok** após manifest).  
3. Commit explícito só dos paths L4/L6/L7 (+ manifest + autonomy) **ou** separar do `os-runtime.ps1` em dois commits.

---

## Fora de scope (registado)

- Novos scripts (`classify-change.sh`, `autonomous-commit-gate.sh`, etc.).  
- Novos JSON Schemas.  
- Alteração à lógica de build/test dos validadores.  
- Push/deploy/release (aprovação humana).
