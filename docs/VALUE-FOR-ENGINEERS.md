# Valor para o engenheiro de desenvolvimento

Este repositório resolve um problema muito concreto na vida de um engenheiro de desenvolvimento:

**transforma** o uso de agentes como Claude Code, Cursor ou Codex de uma **prática improvisada** para um **processo operacional** com memória, regras, validação, segurança e continuidade.

Ou seja, **reduz o caos** de trabalhar com IA em código real.

**Cópia integral (texto plano):** [`VALUE-FOR-ENGINEERS.plain.txt`](VALUE-FOR-ENGINEERS.plain.txt) — mesmo conteúdo narrativo, sem tabelas nem links de repo; útil para colar noutros sítios.

**Related:** `README.md`, `ARCHITECTURE.md`, `docs/AUTONOMY.md`, `docs/QUICKSTART.md`, `policies/auto-approve-matrix.md`, `policies/invariants.md`, `docs/VALIDATION.md`, `docs/REPO-BOUNDARIES.md`, `docs/WORKFLOW-STATES.md`.

---

## 1. O agente deixa de começar do zero em cada sessão

### Problema comum

Um engenheiro abre uma nova sessão com Claude/Cursor e o agente não sabe:

- em que branch está o trabalho
- o que foi decidido ontem
- que riscos estavam abertos
- que comandos validam o projeto
- que áreas são críticas
- que estilo de engenharia seguir
- que mudanças já foram tentadas e falharam

**Resultado:** repetição, perda de contexto e decisões inconsistentes.

### O que o Claude OS resolve

Cria uma camada de **memória e contexto**:

- `.claude/session-state.md`
- `.claude/learning-log.md`
- `CLAUDE.md`
- `.agent/operating-contract.md`
- `heuristics/`
- `policies/`

### Impacto na vida do engenheiro

- Menos tempo a explicar tudo de novo.
- Menos risco de o agente repetir erros.
- Mais continuidade entre sessões.

---

## 2. Reduz microgestão do agente

### Problema comum

O agente pergunta demais: *Posso ler este ficheiro?* *Posso correr testes?* *Posso fazer git diff?* *Posso auditar isto?* *Posso procurar usos?*

Isso torna o engenheiro num **operador de botões**.

### O que o Claude OS resolve

Define uma **matriz clara** (`policies/auto-approve-matrix.md`, L4 no operating contract):

| Área | Comportamento |
|------|----------------|
| Read-only | autónomo |
| Testes / typecheck / lint | autónomo |
| Correções reversíveis | autónomas **com** validação |
| Produção / release / secrets / migrations | **aprovação humana** |

### Impacto

O engenheiro deixa de aprovar micro-passos e **só intervém onde há risco real**.

---

## 3. Evita autonomia perigosa

### Problema comum

O agente pode fazer alterações demasiado amplas ou perigosas:

- mexer em auth
- alterar migrations
- mudar RLS
- apagar ficheiros
- relaxar validações
- tocar em secrets
- preparar deploy/release sem gate

### O que o Claude OS resolve

Define **fronteiras de risco** e **gates humanos** (`policies/invariants.md`, `policies/autonomy-policy.json`, `docs/REPO-BOUNDARIES.md`):

Production · Release · Migration · Auth/RLS · Secrets · Destructive changes · Policy relaxation · Validator bypass

### Impacto

O engenheiro ganha **autonomia sem perder controlo**.

---

## 4. Evita “falso verde”

### Problema comum

O agente diz: *Está tudo verde.* Mas na prática:

- um teste foi skipped
- Bash não estava disponível
- CI não correu
- schema não foi validado
- houve warnings ignorados
- um check falhou mas foi tratado como aceitável

### O que o Claude OS resolve

Impõe a regra (`runtime-budget.json` → `neverTreatAsPassed`, `policies/invariants.md` I-001, `docs/DEGRADED-MODES.md`):

- **warn** não é pass
- **skip** / **skipped** não é pass
- **unknown** não é pass
- **degraded** não é pass
- **not_run** não é pass
- **blocked** não é pass

### Impacto

O engenheiro **não** recebe confiança falsa. Recebe **estado honesto**.

---

## 5. Padroniza como projetos são preparados para IA

### Problema comum

Cada projeto tem uma forma diferente de usar IA: um tem `CLAUDE.md`, outro `AGENTS.md`, outro regras no Cursor, outro não tem nada, outro tem docs obsoletos.

### O que o Claude OS resolve

Cria um **bootstrap padronizado**:

- `init-project` (`init-project.ps1`)
- `templates/`
- `policies/`
- `templates/commands`
- session memory (`.claude/`)
- skills (`source/skills/`)
- operating contract (`.agent/`)

### Impacto

Todos os projetos ficam com uma **base comum** para agentes trabalharem bem.

---

## 6. Faz o agente respeitar o contexto do projeto

### Problema comum

O agente sugere soluções genéricas que não respeitam:

- stack do projeto
- comandos reais
- estilo do repo
- restrições de produção
- arquitetura existente
- áreas críticas

### O que o Claude OS resolve

Fornece **contexto canónico**:

- `CLAUDE.md` do projeto
- `policies/`
- `heuristics/`
- session-state
- `docs/REPO-BOUNDARIES.md`
- operating contract

### Impacto

As respostas e mudanças ficam mais **alinhadas com a realidade** do projeto.

---

## 7. Reduz drift entre Claude, Cursor e Codex

### Problema comum

Claude Code segue uma regra, Cursor segue outra, Codex outra → comportamento inconsistente, instruções duplicadas, regras divergentes, prompts obsoletos.

### O que o Claude OS resolve

Define uma **fonte canónica** e adapters:

- `source/skills/`
- `CLAUDE.md`
- `AGENTS.md`
- `.cursor/rules/`
- `.agent/`
- `agent-adapters-manifest.json`

### Impacto

Vários agentes passam a operar com a **mesma disciplina**.

---

## 8. Torna skills reutilizáveis e governadas

### Problema comum

Prompts úteis ficam espalhados: num chat antigo, num README, numa nota pessoal, numa regra do Cursor, numa skill copiada manualmente.

### O que o Claude OS resolve

Transforma skills em **artefactos versionados**:

- `source/skills/`
- `skills-manifest.json`
- `SKILL.md`
- sync-skills
- `verify-skills` / `verify-skills-structure` / economia conforme perfil

### Impacto

O engenheiro cria **capacidades reutilizáveis** em vez de repetir prompts.

---

## 9. Melhora validação antes de CI/CD

### Problema comum

O engenheiro só descobre problemas quando: CI falha, PR review aponta erro, deploy quebra, produção reclama.

### O que o Claude OS resolve

Cria **validação local por perfis** (`tools/os-validate.ps1`, `docs/VALIDATION.md`):

| Perfil | Papel |
|--------|--------|
| **quick** | feedback rápido |
| **standard** | validação normal |
| **strict** | release / CI-style |

O Claude OS **não substitui** CI/CD — melhora inputs **a montante** (`README.md`, `ARCHITECTURE.md`).

### Impacto

Mais problemas são apanhados **antes** de abrir PR ou antes do CI.

---

## 10. Ajuda a trabalhar em Windows, Linux e CI com menos confusão

### Problema comum

Muitos projetos sofrem com diferenças de ambiente: Bash ausente no Windows, CRLF gera diff falso, Git Bash/WSL diferente de Linux CI, scripts funcionam só numa máquina.

### O que o Claude OS resolve

Regista **heurísticas** e **modos degradados** (`docs/COMPATIBILITY.md`, `docs/DEGRADED-MODES.md`):

- Bash missing → warn local, fail strict/CI (conforme perfil e flags)
- CRLF noise → verificar diff ignorando CRLF onde aplicável
- Git checkout ausente → warning/failure conforme perfil

### Impacto

Menos tempo perdido com problemas de **ambiente**.

---

## 11. Dá rastreabilidade às decisões

### Problema comum

Depois de algumas sessões ninguém sabe: por que isto foi alterado, quem aprovou, que validação passou, que risco ficou aberto, qual era o rollback.

### O que o Claude OS resolve

Cria **trilhos**:

- session-state
- decision-log (templates)
- `docs/OPERATOR-JOURNAL.md`
- validation history (`docs/VALIDATION.md`, `logs/` quando usado)
- `docs/AUDIT-EVIDENCE.md`

### Impacto

O engenheiro consegue **reconstruir a história** da mudança.

---

## 12. Ajuda a priorizar riscos

### Problema comum

O agente mistura tudo (typo, bug médio, segurança, deploy, auth, docs) com o **mesmo peso**.

### O que o Claude OS resolve

Classifica **severidade** e **superfície** (`docs/HAZARDS.md`, `docs/RISK-ENERGY.md`, matriz de autonomia):

- low / medium / high / critical
- read-only / reversible / destructive / production / security / release / migration

### Impacto

O engenheiro sabe **o que atacar primeiro**.

---

## 13. Evita que documentação, scripts e realidade se separem

### Problema comum

Com o tempo: README manda correr comando que não existe; manifest aponta para ficheiro antigo; skill diz uma coisa; script espera outra; CI executa terceiro caminho.

### O que o Claude OS resolve

Propõe e/ou **valida contratos**: doc-contract audit, manifest validation, schema validation, adapter drift, `docs/REPO-BOUNDARIES.md`.

### Impacto

Menos documentação **mentirosa**. Menos onboarding **quebrado**.

---

## 14. Ajuda em auditorias técnicas

### Problema comum

Pedir ao agente “audita o repo” gera um relatório solto, difícil de reproduzir.

### O que o Claude OS resolve

Define **como auditar** (`docs/WORKFLOW-STATES.md`, playbooks):

- ler primeiro
- classificar severidade
- separar read-only de writes
- separar autónomo de gated
- gerar evidência
- não aplicar fixes críticos sem aprovação

### Impacto

Auditorias ficam **acionáveis** e **seguras**.

---

## 15. Ajuda a fechar sessões com continuidade

### Problema comum

No fim da sessão, o agente fez coisas, mas nada fica preparado para a próxima.

### O que o Claude OS resolve

Cria **rotina de fecho** (`templates/commands`, digest/absorb onde existir):

- o que mudou
- validações corridas
- riscos abertos
- próximos passos
- rollback
- fora de escopo
- estado da branch

### Impacto

A próxima sessão começa com **contexto real**, não com memória perdida.

---

## 16. Reduz dívida operacional

### Problema comum

Projetos acumulam: scripts não usados, políticas antigas, skills duplicadas, docs obsoletos, generated files editados manualmente, config local misturada com repo.

### O que o Claude OS resolve

Força **separação** (`policies/invariants.md` I-002, I-003):

- canonical source
- generated targets
- local-only state
- versioned policy
- ignored context/logs

### Impacto

Menos **lixo operacional** e menos comportamento **imprevisível**.

---

## 17. Torna o engenheiro mais produtivo sem abdicar de controlo

### O maior ganho

**Antes**

- engenheiro explica
- agente pergunta
- engenheiro aprova
- agente tenta
- engenheiro corrige
- agente esquece

**Depois**

- agente lê contexto
- audita autonomamente (read-only onde aplicável)
- aplica fixes reversíveis
- valida
- gera evidência
- escala só risco real
- regista estado

O engenheiro passa a atuar como **arquiteto**, **revisor de risco**, **decisor de produto**, **aprovador de superfície crítica** — não como operador de comandos repetitivos.

---

## Resumo numa frase

O Claude OS desloca esforço repetitivo e ambiguidade para **contratos, memória e validação** — e reserva o humano para **transições de risco** e **juízo**, com **estado honesto** em vez de falso verde.
