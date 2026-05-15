# Capacidades operacionais desejadas

## Fluxo-alvo

1. Inicializa o runtime.
2. O OS diagnostica o ambiente.
3. O OS escolhe perfil de validação.
4. O OS carrega skills certas.
5. O OS verifica drift.
6. O OS executa playbook apropriado.
7. O OS valida outputs.
8. O OS gera evidência.
9. O OS bloqueia falso verde.
10. O humano aprova superfícies críticas.

Abaixo está a descrição profissional de cada capacidade. **Nesta versão do documento** estão desenvolvidas: **§2** diagnóstico, **§3** perfis de validação, **§4** inicialização do runtime (passo **1** do fluxo-alvo), **§5** carregamento de *skills* (passo **4** do fluxo-alvo), **§6** verificação de *drift* (passo **5** do fluxo-alvo), **§7** execução de *playbooks* (passo **6** do fluxo-alvo), **§8** validação de *outputs* (passo **7** do fluxo-alvo), **§9** geração de evidência (passo **8** do fluxo-alvo), **§10** bloqueio de falso verde (passo **9** do fluxo-alvo), **§11** aprovação humana em superfícies críticas (passo **10** do fluxo-alvo). As secções **14** (competências técnicas por domínio), **15** (maturidade de engenharia), **16** (resultado final esperado) e **17** (modelo de autonomia A0–A4 e alvo 95/5) fecham o arco em conjunto.

**Relacionado:** [O que o Claude OS não deve ser](POSICIONAMENTO-NAO-E.md) · [Arquitetura (EN)](../ARCHITECTURE.md) · [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

## 2. Diagnóstico do ambiente

### Objetivo

Determinar se a workspace local consegue executar validações, bootstrap e operações de desenvolvimento com confiança adequada.

### Capacidade

O Claude OS deve diagnosticar:

- presença de Git
- estado do working tree
- versão do PowerShell
- presença de Bash
- compatibilidade Windows/Linux/macOS
- disponibilidade de scripts essenciais
- validade de manifestos
- integridade de schemas
- permissões básicas de leitura/escrita

Cada *finding* de diagnóstico deve poder ser expresso com **status**, **reason**, **impact**, **remediation** e **strictImpact** (e, na implementação atual, também **`name`**, **`detail`** e opcionalmente **`docsLink`**).

**Implementação**

- **Entrada principal:** `pwsh ./tools/os-runtime.ps1 doctor` → `tools/os-doctor.ps1` (somente leitura; não muta o repo). Saída JSON com `-Json`: agrega `environment` (SO, `pwshVersion`, disponibilidade de git/bash/node/npm), `repo` (ramo, *dirty*, *ahead/behind* quando há `.git`) e lista **`checks`**.
- **Git e working tree:** verifica-se o comando `git`; lê-se ramo e estado sujo via `git status` (com orçamento de tempo no *doctor* para evitar bloqueios).
- **PowerShell:** verifica-se `pwsh` na PATH (necessário para validadores e bootstrap em Windows).
- **Bash:** por omissão ausência de `bash` é **aviso** (`warn`); com `-RequireBash` no *health* pré-condicional exige-se bash. `-SkipBashSyntax` alinha expectativa em Windows sem Bash.
- **SO:** campo `environment.os` no JSON (descrição do runtime, p.ex. Windows vs Linux).
- **Scripts e ficheiros canónicos:** o *doctor* confirma existência de caminhos como `bootstrap-manifest.json`, `docs-index.json`, `os-capabilities.json`, `tools/verify-os-health.ps1`, bundles em `templates/invariant-engine/dist`, e sinais opcionais de `.claude/` em repos de aplicação.
- **Validade de manifestos e schemas:** o *doctor* foca-se em **sinais de prontidão** (ficheiros presentes, ferramentas na PATH). A validação **semântica** de manifestos e a **integridade schema↔JSON** fazem parte do agregado **`verify-os-health.ps1`** (por exemplo `verify-bootstrap-manifest`, `verify-json-contracts`). Não confundir “doctor ok” com “release contracts ok” sem correr o *health* / perfil desejado.
- **Permissões de leitura/escrita:** o *doctor* **não** executa hoje um teste dedicado de ACL de ficheiros; assume-se leitura no repo e que escrita pontual (por exemplo `logs/` no `init`) falha de forma visível se o SO negar. Extensões futuras podem acrescentar checagens explícitas.

Exemplo de objeto dentro de **`checks`** (campos alinhados ao JSON de `os-doctor.ps1 -Json`; para entradas não-`ok`, `reason`/`impact`/`remediation`/`strictImpact` vêm de `tools/lib/os-remediation-guidance.ps1` quando não são passados explicitamente):

```json
{
  "name": "bash",
  "status": "warn",
  "detail": "bash not found",
  "reason": "bash not found",
  "impact": "Bash syntax checks and hook scripts are skipped or weakened on this machine.",
  "remediation": "Install Git Bash or WSL, add bash to PATH, then re-run doctor. See docs/TROUBLESHOOTING.md (Bash missing on Windows).",
  "strictImpact": "os-validate -Profile strict and verify-os-health -Strict treat unexpected doctor warnings as failures.",
  "docsLink": "docs/TROUBLESHOOTING.md"
}
```

### Valor de engenharia

O diagnóstico deixa de ser binário. O sistema passa a distinguir:

- ambiente saudável
- ambiente degradado mas utilizável
- ambiente inadequado para strict/release
- ambiente bloqueado

Isto é essencial em sistemas críticos porque nem toda degradação deve bloquear desenvolvimento local, mas nenhuma degradação deve ser vendida como sucesso.

---

## 3. Seleção de perfil de validação

### Objetivo

Aplicar validação **proporcional** ao risco e ao custo.

### Perfis

| Perfil | Uso típico |
|--------|------------|
| **quick** | Pré-voo local barato |
| **standard** | Desenvolvimento normal |
| **strict** | CI, release e superfícies críticas |

### Quick

Para **preflight** local barato.

**Deve** privilegiar:

- verificação de contratos JSON e manifestos essenciais
- orçamentos de runtime e economia de contexto (sinais baratos)
- *skills* canónicos (manifesto, estrutura, `verify-skills`) sem varrer toda a superfície de release
- checagens rápidas de existência e coerência onde o custo for baixo

**Não** deve, por omissão, impor smoke tests caros nem varrer todas as superfícies pesadas de release **sem necessidade** (o desenho-alvo é manter o *quick* mais barato que *standard*).

### Standard

Para **desenvolvimento normal**.

**Inclui** o espírito do *quick* e acrescenta camadas como:

- índice de documentação, *skills* (economia, *drift*), memória de sessão
- *adapters* de agentes e *drift* (como aviso quando aplicável)
- *git hygiene* honesto (incl. checkout sem `.git` como aviso quando configurado)
- `doctor` / diagnóstico após a bateria de scripts de perfil
- consistência adicional de contratos e manifestos exposta pelos verificadores do orquestrador

Pode emitir **warnings honestos** em ambientes locais; o orquestrador **não** trata `warn`/`skip` como sucesso verde (saída ≠ 0 quando só há avisos, conforme política do `os-validate.ps1`).

### Strict

Para **CI**, **release** e superfícies **críticas**.

**Inclui** o espírito do *standard* e endurece:

- passagem de **`-Strict`** a verificadores que suportam modo estrito (*script-manifest*, *components*, *skills-manifest*, *skills-structure*, *playbooks*, *recipes*, *no-secrets*, *upgrade-notes*, *skills-drift*, *deprecations*)
- encadeamento final com **`os-validate-all.ps1 -Strict`** (agregado *release*): *health* completo, sintaxe **Bash** quando `bash` está no PATH e não se usou `-SkipBashSyntax` (comportamento tipo `-RequireBash`), smoke de *bootstrap* em projeto temporário, verificação de sintaxe PowerShell em massa via *health*, e restantes gates do agregado
- *adapter drift* pode falhar de forma bloqueante com **`-FailOnDrift`**
- reforço explícito contra **falso verde** (estados `warn`/`skip`/`unknown` não contam como “passou”)

### Valor de engenharia

Isto evita dois extremos perigosos:

- validação **fraca** em mudanças críticas
- validação **pesada demais** para tarefas simples

O sistema passa a aplicar a **quantidade certa de rigor** no momento certo.

### Implementação (`tools/os-validate.ps1`)

Comando direto:

```powershell
pwsh ./tools/os-validate.ps1 -Profile quick|standard|strict [-Json] [-SkipBashSyntax] [-WriteHistory]
```

Ou via *runtime*:

```powershell
pwsh ./tools/os-runtime.ps1 validate -ValidationProfile quick|standard|strict [-Json]
```

**Nota importante:** o orquestrador atual corre um **núcleo partilhado** de verificadores em **todos** os perfis (incluindo *quick*) — por exemplo `verify-json-contracts`, `verify-bootstrap-manifest`, `verify-lifecycle`, `verify-distribution`, *quality gates*, *skills* base, *playbooks*, *approval-log*, *recipes*, entre outros. A diferenciação **standard** / **strict** está sobretudo no **bloco adicional** (economia/*drift* de *skills*, *git hygiene*, *no-secrets*, *upgrade-notes*, índice de docs, memória de sessão, *adapters*, *doctor*, *drift* bloqueante, *deprecations* estritas, e por fim **`os-validate-all -Strict`**). Evoluir o *quick* para um subconjunto ainda mais barato seria um **refactor** explícito do script, alinhado ao desenho-alvo desta secção.

---

## 4. Inicialização do runtime

### Objetivo

Transformar um checkout do Claude OS numa workspace operacional previsível, sem exigir conhecimento interno dos scripts.

### Capacidade

O comando de inicialização deve preparar o ambiente local de forma idempotente:

```powershell
pwsh ./tools/os-runtime.ps1 init
```

ou:

```powershell
pwsh ./tools/init-os-runtime.ps1 -Json
```

A inicialização deve:

- resolver a raiz do repositório de forma determinística
- criar contexto local não versionado
- criar diretórios de logs locais
- verificar PowerShell
- verificar Git
- verificar Bash
- sincronizar adapters declarados
- correr doctor/health básico
- emitir envelope JSON

**Implementação** (`tools/init-os-runtime.ps1`): a raiz vem de `Split-Path $PSScriptRoot -Parent`. O contexto local são `OS_WORKSPACE_CONTEXT.md` e `OPERATOR_JOURNAL.md` criados a partir dos templates só se ainda não existirem (entradas em `.gitignore`). `logs/` é criado se faltar. Doctor/health básico: por omissão corre-se `os-doctor.ps1` após a preparação; com `-FullHealth` corre-se `verify-os-health.ps1`. `-Json` emite o envelope do validador; existem também `-SkipBashSyntax`, `-NoValidation`, `-DryRun` e `-WriteHistory` conforme necessidade operacional.

### Valor de engenharia

Isto transforma onboarding em procedimento repetível. Novos operadores deixam de descobrir comandos por tentativa e erro. O runtime passa a ter um ponto de entrada claro, com output legível para humano e máquina.

### Princípio crítico

A inicialização deve ser idempotente. Rodar o comando várias vezes não deve reescrever estado local, gerar diffs desnecessários nem mascarar degradações.

---

## 5. Carregamento de skills corretas

*(No fluxo-alvo em dez passos, este tema é o **passo 4**; aqui usa-se **§5** para não colidir com a §4 «Inicialização», que cobre o passo 1 do fluxo.)*

### Objetivo

Gerir capacidades dos agentes como **componentes versionados**, não como *prompts* dispersos.

### Capacidade

Cada *skill* deve ser declarada no manifesto canónico **`skills-manifest.json`** (validado por **`schemas/skills-manifest.schema.json`**), com raiz de conteúdo em **`canonicalRoot`** (tipicamente `source/skills/<id>/SKILL.md`).

Ilustração (campos centrais; no repositório real cada entrada inclui também `name`, `path`, `status`, `summary`, `intendedUse`, `generatedTargets`, `dependencies`, `relatedPolicies`, etc. — ver o *schema*):

```json
{
  "id": "release-readiness",
  "maturity": "stable",
  "status": "active",
  "riskLevel": "critical",
  "allowedAgents": ["claude", "cursor", "codex"],
  "requiresApprovalFor": ["Release", "Production"],
  "contextBudget": {
    "maxLines": 300,
    "maxBytes": 24000
  }
}
```

O sistema deve saber:

- **que** *skills* existem — lista em `skills-manifest.json` alinhada a `source/skills/*`;
- **onde** vivem — campo `path` e `generatedTargets` (cópias geradas em `.claude/skills/`, `.cursor/skills/`, … após *bootstrap*);
- **para que servem** — `summary`, `intendedUse`, corpo em `SKILL.md`;
- **que agentes** podem usá-las — `allowedAgents` (`claude` \| `cursor` \| `codex`);
- **qual o risco** — `riskLevel` (`low` \| `medium` \| `high` \| `critical`);
- **qual a maturidade** — `maturity` (`stable` \| `experimental` \| `internal` \| `deprecated`) e `status` (`active` \| `draft` \| `deprecated`);
- **se precisam de aprovação humana** — `requiresApprovalFor` (tags como `Release`, `Production`, …; ver playbooks, **§11**, e `docs/APPROVALS.md` quando aplicável);
- **quais validações as cobrem** — `verify-skills-manifest`, `verify-skills-structure`, `verify-skills`, `verify-skills-economy`, `verify-skills-drift` (e `test-skills` nos perfis *standard*/*strict* via `os-validate.ps1`); mapeamento de *skills* em **`component-manifest.json`** para `verify-components.ps1`; roteamento de intenção em **`route-capability.ps1`** / `os-capabilities.json`.

**Implementação:** `bootstrap-manifest.json` fixa contagens canónicas; `init-project.ps1` materializa *skills* no projeto; `tools/sync-skills.ps1` mantém cópias geradas alinhadas ao manifesto quando usado no fluxo de manutenção. Manual do operador: **[docs/SKILLS.md](SKILLS.md)**.

### Valor de engenharia

Isto transforma *skills* em **capabilities governadas**.

Em vez do agente carregar contexto arbitrário, o Claude OS seleciona capacidades **compatíveis com a tarefa**, o **risco** e o **perfil operacional** (ver §3 e `runtime-profiles.json` / documentação de perfis).

### Competência resultante

- *agent capability management*
- *skill lifecycle governance*
- *multi-agent skill portability*

---

## 6. Verificação de drift

*(No fluxo-alvo em dez passos, isto corresponde ao **passo 5** — *O OS verifica drift*.)*

### Objetivo

Garantir que documentos, *skills*, *adapters*, manifestos e *scripts* continuam **alinhados** entre si e com o que os validadores e a documentação prometem.

### Drift a detetar

| Sinal de drift | Cobertura típica (ferramentas / artefactos) |
|----------------|-----------------------------------------------|
| *Skill* canónica diferente da cópia gerada | `verify-skills-drift.ps1` (com `-Strict` em perfil *strict*); `skills-manifest.json` → `generatedTargets` vs `source/skills/.../SKILL.md` |
| *Adapter* Claude / Cursor / Codex editado à mão sem alinhar ao manifesto | `verify-agent-adapters.ps1`, `verify-agent-adapter-drift.ps1` (`-FailOnDrift` em *strict*), `agent-adapters-manifest.json`, `templates/adapters/` |
| README ou INDEX menciona comando inexistente | `verify-doc-contract-consistency.ps1`, `verify-doc-manifest.ps1` (INDEX vs `bootstrap-manifest.json`) |
| Manifesto aponta para *script* removido | `verify-script-manifest.ps1` (paths listados vs disco), `verify-bootstrap-manifest.ps1` |
| *Schema* referenciado não existe ou JSON não cumpre contrato | `verify-json-contracts.ps1`, `schemas/*.schema.json` |
| *Playbook* inconsistente ou caminho inválido | `verify-playbooks.ps1`; referências a validadores obsoletos cruzam com **`deprecation-manifest.json`** + `verify-deprecations.ps1` (*strict*) |
| Perfil *strict* depende de componente experimental / *deprecated* sem *allowlist* | `verify-components.ps1 -Strict` vs `component-manifest.json` (`strictReleaseExperimentalAllowlist`) |
| `ARCHITECTURE.md` (e contrato de release) divergem do verificador | `verify-runtime-release.ps1` (inclui substrings exigidas em docs de release) |

Outros sinais úteis no mesmo espírito: *git hygiene* (`verify-git-hygiene.ps1`), *skills economy* (`verify-skills-economy.ps1`), *docs index* (`verify-docs-index.ps1`).

### Valor de engenharia

*Drift* é uma das causas mais comuns de falha em sistemas operacionais internos. **Não** aparece como *crash* imediato; aparece como **confiança falsa**.

O Claude OS deve tratar *drift* como **degradação operacional**:

- em **local** / perfis leves → **aviso explícito** (`warn`) quando a política o permitir;
- em ***strict* / release / CI** → **falha** (`fail`) quando o contrato exige (por exemplo *drift* de *skills* estrito, `verify-agent-adapter-drift -FailOnDrift`, `verify-components -Strict`, `verify-deprecations -Strict` dentro de `os-validate -Profile strict` → `os-validate-all -Strict`).

### Princípio crítico

Um sistema crítico não falha apenas quando o **código** quebra. Também falha quando **documentação**, **manifestos** e ***tooling*** deixam de descrever a **mesma realidade**.

### Implementação

Os verificadores acima correm no agregado **`verify-os-health.ps1`** e/ou em **`os-validate.ps1`** (*quick* / *standard* / *strict*) conforme §3; *drift* de *skills* e vários destes passos entram em **standard** e **strict**. Para correr só um verificador durante diagnóstico, invocar o `tools/verify-*.ps1` correspondente com **`-Json`**.

---

## 7. Execução de playbooks apropriados

*(No fluxo-alvo em dez passos, isto corresponde ao **passo 6** — *O OS executa playbook apropriado*.)*

### Objetivo

Guiar operações complexas através de **sequências verificáveis** (*runbooks*), em vez de procedimentos implícitos ou improvisação.

### Playbooks principais

O catálogo canónico está em **`playbook-manifest.json`** (pasta `playbooks/`, *schema* `schemas/playbook-manifest.schema.json`). **Nesta versão do repositório** existem os seguintes *playbooks*:

| ID | Ficheiro | Risco (manifesto) |
|----|-----------|-------------------|
| `release` | `playbooks/release.md` | critical |
| `incident` | `playbooks/incident.md` | critical |
| `migration` | `playbooks/migration.md` | high |
| `bootstrap-project` | `playbooks/bootstrap-project.md` | medium |
| `docs-contract-audit` | `playbooks/docs-contract-audit.md` | medium |
| `adapter-drift-repair` | `playbooks/adapter-drift-repair.md` | high |

Nomes como **security-review** ou **skill-authoring** podem existir como *recipes*, *commands* em `templates/commands/`, ou futuros *playbooks* — só entram nesta camada quando forem declarados em **`playbook-manifest.json`** e tiverem corpo em `playbooks/*.md`.

### O que cada playbook deve declarar

O contrato Markdown exige cabeçalhos com títulos **fixos** (ver **[playbooks/README.md](../playbooks/README.md)**). Mapeamento entre a tua lista e esses títulos:

| Conceito (descrição) | Cabeçalho obrigatório no `.md` |
|----------------------|----------------------------------|
| *trigger* | `## Trigger conditions` |
| *inputs* | `## Required inputs` |
| *risk level* | `## Risk level` |
| *required approvals* | `## Required approvals` |
| *preflight checks* | `## Preflight checks` |
| *steps* | `## Execution steps` |
| *validation* | `## Validation steps` |
| *rollback / abort criteria* | `## Rollback / abort criteria` |
| *evidence* | `## Evidence to collect` |
| *expected outputs* | `## Expected outputs` |
| *failure reporting* | `## Failure reporting` |

Além disso: **`## Purpose`** (contexto e intenção do *playbook*).

**`-Strict`** em `verify-playbooks.ps1` trata secções em falta como **falha** para *playbooks* de risco **high** / **critical** (e reforça o contrato completo).

### Valor de engenharia

*Playbooks* reduzem **variabilidade humana** e **variabilidade do agente**.

Numa operação crítica, o agente **não** deve improvisar: deve seguir uma sequência **definida, verificável e auditável** (incluindo, quando aplicável, o **ledger de aprovações** humanas — **§11**, `playbooks/README.md`, `docs/APPROVALS.md`).

### Competência resultante

- *operational runbook orchestration*
- *critical workflow governance*
- *incident / release / migration discipline*

### Implementação

```powershell
pwsh ./tools/verify-playbooks.ps1 -Json
pwsh ./tools/verify-playbooks.ps1 -Strict -Json
```

O *health* / `os-validate` invoca `verify-playbooks` nos perfis relevantes (§3). Descoberta de rota para capacidades pode usar **`route-capability.ps1`** / `os-capabilities.json` em conjunto com o manifesto de *playbooks*.

---

## 8. Validação de outputs

*(No fluxo-alvo em dez passos, isto corresponde ao **passo 7** — *O OS valida outputs*.)*

### Objetivo

**Não** confiar no facto de um *script* ter corrido. Validar o **resultado produzido** (artefactos no disco, JSON de estado, árvore de projeto, contratos documentais).

### Exemplos

**Após *sync* de *skills*** (por exemplo `tools/sync-skills.ps1`):

- confirmar que **`generatedTargets`** existem e são legíveis;
- confirmar que o conteúdo **bate com a fonte canónica** `source/skills/<id>/SKILL.md` — `verify-skills-drift.ps1`, `verify-skills-structure.ps1`;
- confirmar que **não há *drift*** entre canónico e cópias — §6.

**Após *bootstrap* de projeto** (`init-project.ps1`):

- confirmar estrutura **`.claude/`** (e *adapters* esperados) — *smoke* em `verify-os-health.ps1` / `os-validate-all.ps1` (`Test-BootstrapSmoke` + ferramentas geradas no temp project);
- confirmar **manifestos** e contagens — `verify-bootstrap-manifest.ps1`;
- confirmar **session memory** e artefactos de sessão — `verify-session-memory.ps1`;
- confirmar **commands** / *templates* referenciados — `verify-bootstrap-manifest.ps1`, contagens em `INDEX.md` via `verify-doc-manifest.ps1`;
- confirmar **políticas** copiadas onde aplicável — *smoke* e revisão de caminhos em `bootstrap-manifest.json` (`projectBootstrap.criticalPaths`).

**Após alteração documental** (README, INDEX, docs):

- confirmar **ligações** e referências internas — `verify-skills.ps1` (ligações em *skills*), `verify-docs-index.ps1`;
- confirmar **comandos documentados** vs *scripts* reais — `verify-doc-contract-consistency.ps1`;
- confirmar **contrato com manifestos** (contagens, caminhos) — `verify-doc-manifest.ps1`, `verify-doc-contract-consistency.ps1`.

### Valor de engenharia

Isto muda a lógica de:

**comando executou**

para:

**estado final verificado**.

Em sistemas críticos, o **segundo** é o único aceitável.

### Implementação

Os verificadores emitem, quando usam **`-Json`**, envelopes (`New-OsValidatorEnvelope` / *status* `ok` \| `warn` \| `fail`). Orquestradores como **`os-validate.ps1`** leem a última linha JSON e tratam `warn`/`skip` como **não-sucesso** para fins de saída do processo (§3; taxonomia e política completas em **§10**). **`run-contract-tests.ps1`** reforça exemplos de envelopes e contratos JSON em `tests/contracts/`.

---

## 9. Geração de evidência

*(No fluxo-alvo em dez passos, isto corresponde ao **passo 8** — *O OS gera evidência*.)*

### Objetivo

Produzir **artefactos auditáveis** sobre o que foi verificado, **quando**, com que **perfil** e com que **resultado** — para humanos e para máquinas.

### Evidência desejada

| Tipo | Onde costuma aparecer |
|------|------------------------|
| *Validation result* | Envelope JSON de `os-validate.ps1`, `os-validate-all.ps1`, `verify-os-health.ps1`, `init-os-runtime.ps1` (com `-Json`); *schemas* `schemas/os-validator-envelope.schema.json`, `schemas/os-health-envelope.schema.json` |
| *Manifest* / *skills* / resumos agregados | Dentro de `checks[]` / `warnings` / `failures` dos envelopes; *health* agrega dezenas de passos com `latency_ms` |
| *Adapter drift* | `verify-agent-adapter-drift.ps1 -Json`; entradas em *warnings* / *failures* do orquestrador |
| *Git hygiene* | `verify-git-hygiene.ps1 -Json` |
| *Environment summary* | `os-doctor.ps1 -Json` (`environment`, `repo`) |
| *Warnings* / *failures* | No envelope canónico (`schemas/os-validator-envelope.schema.json`), *warnings* e *failures* são **arrays de *strings***; nunca tratadas como “verde” só porque o processo terminou (§3, §8) |
| *Duration per check* | `verify-os-health` / passos com `latency_ms`; `os-validate` com `durationMs` no envelope |
| *Approval references* | **`logs/approval-log.jsonl`** (append-only) via `append-approval-log.ps1`; *schema* `schemas/approval-log.schema.json`; **`docs/APPROVALS.md`**; enquadramento operacional **§11** |

### Formatos preferenciais

- **JSON** — saída compacta `-Json` / `-Compress` nos comandos de validação e diagnóstico.
- **JSONL** — histórico opcional **`logs/validation-history.jsonl`** (um objeto JSON por linha), escrito por **`tools/write-validation-history.ps1`** quando se passa **`-WriteHistory`** em `init`, `validate`, `verify-os-health` ou `os-validate-all` (directório `logs/` tipicamente em `.gitignore`).
- **Markdown / texto resumido** — modo interativo sem `-Json` (*status lines*, sumários no terminal).

Evidência de *audit* adicional (pacotes, manifestos de evidência): **`tools/export-audit-evidence.ps1`**, **`docs/AUDIT-EVIDENCE.md`**.

### Exemplo (ilustrativo)

O envelope **`os-validate`** (com `-Json`) segue `New-OsValidatorEnvelope`: `tool`, `status`, `durationMs`, `checks[]` (`name`, `status`, `detail` opcional), `warnings[]` e `failures[]` como *strings*, `findings[]` (ex.: `{ "profile": "strict" }`), `actions[]`. O *timestamp* aparece no registo opcional de **histórico** (`-WriteHistory` → `logs/validation-history.jsonl`), não no envelope JSON da última linha.

```json
{
  "tool": "os-validate",
  "status": "fail",
  "durationMs": 42817,
  "checks": [
    { "name": "verify-agent-adapter-drift", "status": "fail", "detail": "exit 1" }
  ],
  "warnings": [],
  "failures": [
    "verify-agent-adapter-drift failed"
  ],
  "findings": [{ "profile": "strict" }],
  "actions": []
}
```

### Valor de engenharia

A evidência permite:

- revisão assíncrona  
- *debugging*  
- auditoria interna  
- *release readiness*  
- comparação entre **local** e **CI**  
- **prova** de não conformidade  

Sem evidência, “passou” é apenas uma **afirmação**. Com evidência, é um **contrato verificável**.

### Implementação

```powershell
pwsh ./tools/os-validate.ps1 -Profile strict -Json -WriteHistory
pwsh ./tools/verify-os-health.ps1 -Json -WriteHistory
```

Garantir redacção de segredos via **`tools/lib/safe-output.ps1`** nos caminhos que expõem texto ao operador ou ao ficheiro JSONL.

---

## 10. Bloqueio de falso verde

*(No fluxo-alvo em dez passos, isto corresponde ao **passo 9** — *O OS bloqueia falso verde*.)*

### Objetivo

Impedir que validações **parciais**, **ignoradas** ou **degradadas** sejam apresentadas como **sucesso** — no terminal, no JSON e na interpretação humana.

### Taxonomia de estados

Estados usados nos contratos JSON e na política de agregação (ver **`schemas/os-validator-envelope.schema.json`**, **`schemas/os-health-envelope.schema.json`**, **`runtime-budget.json`** → `neverTreatAsPassed`, **`docs/VALIDATION.md`**, **`docs/QUALITY-GATES.md`**):

| Estado | Notas |
|--------|--------|
| **ok** | Único estado que equivale a “passou” para **gates de libertação** quando nada mais está em falha. |
| **warn** | Achado não bloqueante no verificador — **não** é *ok* para interpretação *strict* / *release*. |
| **fail** | Bloqueante. |
| **skip** | Verificação não executada (ex.: política local, dependência ausente) — **não** é *ok*. Nos *quality gates*, o alias **`skipped`** alinha com o mesmo significado. |
| **blocked** | Execução ou decisão impedida — tratar como não-verde até resolvido. |
| **degraded** | Capacidade reduzida ou resultado duvidoso — não-verde. |
| **unknown** | Estado não determinado ou não propagado corretamente — não-verde. |
| **not_run** | Passo ou gate não corrido — não-verde (explícito em `neverTreatAsPassed` e em *gates*). |

No envelope agregado de **`verify-os-health.ps1`**, o campo de topo `status` é apenas **`ok` \| `warn` \| `fail`**; cada linha em `checks[]` pode ainda reportar **`skip`** (e campos de remediação). O orquestrador **`os-validate.ps1`** promove `warn`/`skip` vindos de sub-verificadores para **avisos** agregados e **termina com código de saída 1** quando o *status* final não é **`ok`**.

### Regra central

**Apenas `ok` é *ok*.**

- **`warn`** não é *ok*.  
- **`skip`** não é *ok*.  
- **`unknown`** não é *ok*.  
- **`degraded`** não é *ok*.  
- **`not_run`** não é *ok*.  
- **`blocked`** não é *ok*.  
- **`fail`** obviamente não é *ok*.

### Contexto local *versus* *strict* / *release*

- **Local / desenvolvimento:** alguns estados podem ser **aceitáveis para continuar a trabalhar** (ex.: avisos visíveis no sumário humano de `verify-os-health` sem `-Strict`), mas devem **permanecer visíveis** no JSON, no terminal e na evidência (§9) — nunca colapsados silenciosamente em “tudo bem”.
- **Strict / *release*:** estados não-verdes devem **bloquear** (código de saída não zero, agregado não *ok*, *gates* em `quality-gates/`), **salvo exceção formal e documentada** (política explícita, *approval log*, alteração de manifesto de *gates* — não “convenção oral”).

### Valor de engenharia

Esta é uma competência **central** de sistemas críticos. Muitos sistemas falham não porque **não** validaram, mas porque validaram **parcialmente** e declararam **sucesso**.

O Claude OS deve ser **explicitamente hostil** a esse padrão: agregadores que tratam `warn` como sucesso, *pipelines* que ignoram `skip`, ou operadores que só olham para o código de saída **0** sem ler o envelope — são antipadrões que o desenho e a documentação devem desincentivar.

### Implementação

- **`runtime-budget.json`** — lista canónica `neverTreatAsPassed` (inclui `warn`, `unknown`, `not_run`, `degraded`, `blocked` e o alias `skipped`).  
- **`tools/os-validate.ps1`** — `status` agregado **`warn`** ⇒ saída **1** (§3); sub-passos com `warn`/`skip` alimentam mensagens do tipo *not treated as passed*.  
- **`tools/verify-os-health.ps1`** — com **`-Strict`**, qualquer aviso em *checks* falha o processo; modo não-*strict* pode terminar **0** com avisos **ainda listados** no sumário (transparência local — não confundir com *release pass*).  
- **`quality-gates/`**, **`tools/verify-quality-gates.ps1`**, **`docs/QUALITY-GATES.md`**, **`docs/RELEASE-READINESS.md`** — contratos de “sem falso verde” para despacho *release*.  
- Passo **10** do fluxo (aprovação humana): **§11**, **`docs/APPROVALS.md`**, **`append-approval-log.ps1`** — *gate* social sobre superfícies críticas, complementar ao bloqueio técnico acima.

---

## 11. Aprovação humana em superfícies críticas

*(No fluxo-alvo em dez passos, isto corresponde ao **passo 10** — *O humano aprova superfícies críticas*.)*

### Objetivo

Manter **controlo humano** explícito em ações de **alto impacto**, para que decisões de *steward* não dependam de conversa informal nem de memória do operador.

### Superfícies que exigem aprovação

Alinhado a **`runtime-budget.json`** → `approvalRequiredFor`, a manifestação em *playbooks* (`playbook-manifest.json` → `requiresApprovalFor`), e a **`docs/APPROVALS.md`**:

| Classe | Exemplos típicos |
|--------|-------------------|
| **Production** | Tráfego real, configuração de produção, caminhos com dados de clientes |
| **Critical** | Integridade, autenticação, faturação, superfícies de segurança |
| **Incident** | *Break-glass*, comandos de incidente, estabilização em produção |
| **Migration** | Movimento de dados, *cutover*, alterações de *schema* |
| **Release** | *Tags*, promoção em CI de *release*, critérios de despacho |
| **Destructive** | Eliminações, sobrescrituras, infra não idempotente |

*Playbooks* que declaram **qualquer** destas etiquetas devem incluir secção de **ledger de aprovação** no Markdown e obedecer ao contrato em **`docs/APPROVALS.md`**. A validação local de rotina (**`os-validate`**, **`verify-os-health`**, receitas) **não** exige linhas no ledger.

### Requisitos antes de pedir aprovação

Antes de o operador **registar** uma aprovação (ou antes de executar o passo *steward* correspondente), o OS / o *runbook* deve tornar visíveis ao humano (no corpo do *playbook*, *ticket*, ou sumário de sessão):

| Requisito | Onde se materializa no trilho Claude OS |
|-----------|----------------------------------------|
| **Escopo** | Campo **`scope`** do ledger; limites de *blast radius* em texto |
| **Risco** | **`riskLevel`** (`low` \| `medium` \| `high` \| `critical` no *schema*); narrativa de risco pode estender **`operation`** ou **`scope`** |
| **Plano de execução** | **`commandOrActionApproved`** — o que foi aprovado, literal ou referência estável |
| **Plano de rollback** | **`rollbackPlanReference`** — âncora a *playbook*, `docs/`, *ticket*, *change id* (não comando executável opaco) |
| **Validação prévia** | **`relatedValidationEvidence`** — pelo menos um ponteiro (comando + *exit*, *commit*, caminho de envelope JSON, URL de CI) |
| **Evidência disponível** | §9 — ficheiros JSON/JSONL, *paths* listados em **`relatedValidationEvidence`** |
| **Impacto esperado** | Texto no *playbook* ou em **`scope`** / **`operation`**; referência a doc de impacto se existir |
| **Falhas conhecidas** | Transparência no texto pré-execução; ponteiros em **`relatedValidationEvidence`** ou notas ligadas ao *ticket* |
| **Risco residual** | Aceitação explícita pelo **`approver`**; não há campo dedicado no *schema* — documentar na narrativa ou *ticket* e resumir em **`scope`** se necessário |

O *schema* **`schemas/approval-log.schema.json`** fixa os campos **obrigatórios** da linha JSONL; o quadro acima liga **governação** a esses campos.

### Ledger de aprovação

- **Ficheiro:** **`logs/approval-log.jsonl`** (append-only, UTF-8; pasta `logs/` tipicamente em `.gitignore`).
- **Escrita:** **`tools/append-approval-log.ps1`** (obrigatório: **`expirationOrUse`** via **`-ExpiresAt`** e/ou **`-OneTimeUse`**).
- **Verificação estrutural:** **`tools/verify-approval-log.ps1 -Json`** (coerência com *playbooks* e validação de linhas existentes).

Exemplo **alinhado ao *schema*** (nomes canónicos; `operation` é texto livre curto — pode ser `release` ou frase descritiva):

```json
{
  "timestamp": "2026-05-03T12:00:00.0000000Z",
  "operation": "release",
  "riskLevel": "critical",
  "approver": "pending:release-owner",
  "scope": "v1.0.0-pre.1",
  "commandOrActionApproved": "Run strict release validation and prepare release candidate",
  "expirationOrUse": { "oneTimeUse": true },
  "relatedValidationEvidence": [
    "audit/validation-strict.json",
    "pwsh ./tools/os-validate.ps1 -Profile strict -Json exit 0"
  ],
  "rollbackPlanReference": "docs/release-rollback.md"
}
```

*(Nota: um rascunho informal pode falar em `approvedAction` ou `evidence` singular; no repositório o contrato usa **`commandOrActionApproved`** e **`relatedValidationEvidence`** como *array*.)*

### Valor de engenharia

A aprovação humana deixa de ser **verbal e informal**. Passa a ser **parte do trilho operacional**: *append-only*, verificável, ligável a evidência (§9) e coerente com o bloqueio de falso verde (§10).

### Implementação

```powershell
pwsh ./tools/append-approval-log.ps1 `
  -Operation 'Release tag v1.0.0-pre.1' `
  -RiskLevel critical `
  -Approver 'nome@organizacao' `
  -Scope 'repositório X; ambiente staging→prod' `
  -CommandOrActionApproved '…' `
  -OneTimeUse `
  -RelatedValidationEvidence @('…') `
  -RollbackPlanReference 'docs/release-rollback.md' `
  -Json
```

Detalhes em inglês (comandos, *placeholders*, *WhatIf*): **`docs/APPROVALS.md`**. *Skills* de risco elevado: **`docs/SKILLS.md`** (`requiresApprovalFor` no manifesto de *skills*).

---

## 14. Competências técnicas finais do Claude OS

Com as capacidades descritas nas secções anteriores (e os *scripts* / manifestos / *schemas* do repositório), o Claude OS cobre de forma explícita as seguintes áreas de engenharia. Os exemplos entre parênteses apontam para *entrypoints* ou documentação típica — não é uma lista exaustiva de ficheiros.

### 14.1 Platform Engineering

- **Bootstrap** — `bootstrap-manifest.json`, `verify-bootstrap-manifest.ps1`, caminhos críticos de arranque.
- **Configuração de *runtime* local** — `init-os-runtime.ps1`, `os-runtime.ps1`, perfis em `runtime-budget.json`.
- **Inicialização de projeto** — `init-project.ps1`, *templates*, *playbooks* de arranque.
- **Compatibilidade *cross-platform*** — `verify-compatibility.ps1` (matriz vs `script-manifest.json`), `docs/COMPATIBILITY.md`.
- **Geração de *adapters*** — `verify-agent-adapters.ps1`, `verify-agent-adapter-drift.ps1`, *templates* de agente.
- ***Tooling lifecycle*** — `verify-lifecycle.ps1`, `install.ps1` / `install.sh`, `docs/LIFECYCLE.md`.

### 14.2 Site Reliability Engineering

- ***Doctor*** — `os-doctor.ps1` (ambiente e repositório).
- ***Health checks*** — `verify-os-health.ps1`, envelopes JSON agregados (§2, §9).
- **Relatório de degradação** — estados `warn` / `degraded` / `blocked` na taxonomia (§10); sumários honestos no terminal e em JSON.
- ***Playbooks* de incidente** — *playbooks* com etiquetas **Incident** / **Production** e *ledger* (§7, §11).
- **Disciplina de *rollback*** — `rollbackPlanReference` no *ledger*; secções de *rollback* em *playbooks* / `docs/APPROVALS.md`.
- **Latência e *budget*** — `runtime-budget.json`, `verify-runtime-budget.ps1`, `latencyMs` / `totalMs` nos envelopes.

### 14.3 Security Engineering

- **Validação *no-secrets*** — `verify-no-secrets.ps1`, padrões ambíguos em *warn* vs *fail* conforme perfil (§3).
- ***Gates* de aprovação humana** — §11, `append-approval-log.ps1`, `verify-approval-log.ps1`.
- ***Safe apply*** — `docs/SAFE-APPLY.md`, políticas de aplicação gradual.
- **Contenção de ações destrutivas** — `requiresApprovalFor` em manifestos, *playbooks* *steward*, classes **Destructive** / **Migration**.
- **Higiene de dados sensíveis** — `tools/lib/safe-output.ps1`, redacção em envelopes e histórico (§9).

### 14.4 Release Engineering

- **Validação *strict*** — `os-validate.ps1 -Profile strict`, `os-validate-all.ps1 -Strict`.
- ***Release readiness*** — `docs/RELEASE-READINESS.md`, `quality-gates/`, `verify-quality-gates.ps1`.
- ***Upgrade notes*** — `verify-upgrade-notes.ps1`, `schemaVersion` documentada.
- **Empacotamento de distribuição** — `verify-distribution.ps1`, `build-distribution.ps1`, `docs/DISTRIBUTION.md`.
- **Reforço de Git limpo** — `verify-git-hygiene.ps1` (incl. modo *strict* onde aplicável).
- **Evidência de *release*** — §9, `export-audit-evidence.ps1`, `docs/AUDIT-EVIDENCE.md`.

### 14.5 Quality Engineering

- ***Contract tests*** — `run-contract-tests.ps1`, `tests/contracts/`, `docs/CONTRACT-TESTS.md`.
- **Validação de *schemas*** — `schemas/*.schema.json`, `verify-examples.ps1`.
- **Consistência documentação / *runtime*** — `verify-doc-contract-consistency.ps1`, `verify-doc-manifest.ps1`.
- **Testes de regressão de *skills*** — `test-skills.ps1`, manifestos de *skills*.
- **Validação de exemplos** — `examples/`, `verify-examples.ps1`.
- ***Quality gates*** — `quality-gates/*.json`, `docs/QUALITY-GATES.md`.

### 14.6 Knowledge Engineering

- ***Skills lifecycle*** — `verify-skills.ps1`, `verify-skills-manifest.ps1`, `verify-skills-structure.ps1`, `verify-skills-drift.ps1`, `docs/SKILLS.md`.
- **Economia de contexto** — `context-budget.json`, `verify-context-economy.ps1`, `verify-skills-economy.ps1`, `verify-capabilities.ps1`, `docs/CAPABILITIES.md`.
- **Memória local** — `verify-session-memory.ps1`, políticas de sessão.
- ***Operator journal*** — `docs/OPERATOR-JOURNAL.md` (disciplina operacional).
- **Indexação de documentação** — `verify-docs-index.ps1`, `docs-index.json`, `INDEX.md`.
- **Encaminhamento de capacidades** — manifestos de *workflow* / *capabilities*, rotas documentadas.

### 14.7 Agent Governance

- **Modos de risco** — perfis *quick* / *standard* / *strict* (§3); `riskLevel` em *skills* / *playbooks*.
- **Encaminhamento modelo / ferramenta** — `templates/agents`, políticas em `CLAUDE.md` / *skills*.
- **Seleção de *skills*** — §5, manifestos e verificadores.
- **Controlo de *drift* de *adapters*** — §6, `verify-agent-adapter-drift.ps1`.
- **Consistência *multi-agent*** — *templates* partilhados, *adapters* canónicos vs gerados.
- **Política *no false green*** — §10, `neverTreatAsPassed` em `runtime-budget.json`.

---

## 15. Maturidade de engenharia alcançada

### O salto de maturidade

| Antes | Depois |
|--------|--------|
| Conjunto de políticas, *scripts*, *templates* e *prompts* para orientar agentes. | *Runtime* operacional **local-first**, **governado por manifestos**, **auditável**, com validação **proporcional ao risco**, controlo de *drift*, gestão de *skills*, *playbooks* críticos, evidência JSON, economia de contexto e *gates* humanos. |

### Em linguagem de sistemas críticos

O Claude OS passa a fornecer, como sistema integrado:

- deterministic initialization  
- runtime health assessment  
- risk-based validation profiles  
- governed capability loading  
- canonical-source enforcement  
- generated-artifact drift detection  
- operational playbook execution  
- output state verification  
- audit evidence generation  
- false-green prevention  
- human approval gates  

---

## 16. Resultado final esperado

O Claude OS torna-se uma **infraestrutura** que permite a agentes operar com **maior rigor** em projetos reais — sem pretender substituir **humanos**, **CI/CD** ou **produção**. O seu lugar é **melhorar tudo o que acontece antes**: preparação do repositório, contratos, validação local e disciplina operacional a montante dos sistemas formais de entrega.

### O que melhora *antes* da linha de produção

- **Melhor contexto** — políticas, *skills* e orçamentos alinhados ao que o repositório realmente é.  
- **Melhores decisões** — perfis de risco, *playbooks* e encaminhamento de capacidades em vez de improviso contínuo.  
- **Melhor validação** — orquestração proporcional ao risco (§3), *health checks*, contratos JSON.  
- **Menos *drift*** — fontes canónicas, *adapters* verificados, manifestos como verdade operacional (§5–§6).  
- **Menos duplicação** — uma vez definido no manifesto / *schema*, propagado por verificadores.  
- **Menos falso verde** — só **`ok`** é *ok*; estados ambíguos visíveis e bloqueantes onde importa (§10).  
- **Mais evidência** — JSON, JSONL, pacotes de *audit* — “passou” deixa de ser opinião (§9).  
- **Mais controlo humano** — *ledger* e superfícies críticas explícitas (§11).  
- **Maior segurança operacional** — *no-secrets*, *safe apply*, contenção do destrutivo, redacção de dados sensíveis (§14.3).

### Porque a engenharia sobe de nível

O agente deixa de basear-se apenas em **instruções textuais** isoladas e passa a operar **dentro de um sistema** com:

- **contratos**  
- **manifestos**  
- **orquestração**  
- **validação**  
- **evidência**  
- ***gates***  
- **memória**  
- **economia** (de contexto e de superfície)  
- ***rollback*** (disciplina e referências auditáveis)  
- **auditoria**  

Essa é a diferença entre **«usar IA para programar»** e **operar IA dentro de uma disciplina de engenharia crítica** — alinhada a [O que o Claude OS não deve ser](POSICIONAMENTO-NAO-E.md) e ao [posicionamento em arquitetura (EN)](../ARCHITECTURE.md#operational-positioning). O **modelo de autonomia** (níveis A0–A4 e alvo 95/5) está em **§17**.

---

## 17. Autonomia operacional assistida por agentes

### Objetivo

Elevar o Claude OS a um ***runtime* de engenharia assistida por agentes** com **autonomia operacional elevada** nas tarefas de desenvolvimento, validação, documentação, *bootstrap*, *refactor*, auditoria, sincronização e preparação de *release* — **sempre** dentro de contratos, manifestos, validação e *gates* descritos neste documento.

Isto **não** significa substituir **CI/CD**, **produção** ou **julgamento humano** em sistemas críticos (§16, [POSICIONAMENTO-NAO-E.md](POSICIONAMENTO-NAO-E.md)). Significa que o **humano deixa de ser o executor constante** de cada micro-passo repetitivo e passa a ser **aprovedor estratégico** nas **superfícies críticas** (§11) — *Production*, *Critical*, *Incident*, *Migration*, *Release*, *Destructive*, impacto de **segurança** ou **irreversibilidade** relevante.

### 1. Modelo de autonomia (níveis A0–A4)

O sistema deve poder ser descrito e operado com **cinco níveis** de autonomia (A0–A4). São categorias de **postura operacional**, não um *dashboard* medido em tempo real no repositório base.

| Nível | Nome | Significado |
|-------|------|-------------|
| **A0** | *Manual* | O humano executa a cadeia; o agente ou o OS podem existir como referência, sem autonomia de execução. |
| **A1** | *Assistido* | O agente propõe planos, diffs e comandos; o humano aplica, corre validações e decide. |
| **A2** | *Semi-autónomo* | O agente executa tarefas **delimitadas** (ex.: um módulo, um verificador); o humano revê *checkpoints* e integra. |
| **A3** | *Autónomo com gates* | O agente conduz o ciclo local: investigar, planear, editar, testar, validar, corrigir, documentar, sincronizar, gerar evidência e **preparar** mudanças — com **paragem obrigatória** nos *gates* humanos e nas políticas de *strict* / *release*. |
| **A4** | *Autónomo fechado* | Laço fechado **sem** possibilidade de veto humano no momento da ação. **Não permitido** para superfícies *steward* e operações de alto impacto; apenas cenários triviais ou *sandboxes* sem *blast radius* podem aproximar-se disto — e mesmo assim sujeitos a política organizacional. |

### Alvo realista de adoção (Claude OS)

Como **meta de desenho** (não *SLA* contratual nem métrica automática no repo):

- **~95%** do trabalho quotidiano de engenharia assistida no **ciclo local** orientado para **A3** — autonomia com *gates*, evidência e validação proporcional ao risco (§3, §9–§11).  
- **~5%** (ordem de grandeza) de interação humana dedicada a **aprovação estratégica** — quando há impacto crítico, produção, *release*, migração, ação destrutiva, risco de segurança ou **irreversibilidade** que exija *sign-off* explícito no *ledger* ou no processo da organização.

O rácio real depende do projeto, da equipa e da maturidade dos manifestos; o Claude OS **fornece o trilho** para que A3 seja seguro e auditável, não **garante** percentagens.

### Implicações

- O agente **pode** (em A3, com as ferramentas do repositório) investigar, planear, editar, testar, validar, corrigir, documentar, sincronizar, gerar evidência e preparar entregas **até** ao limite definido por políticas e perfis.  
- O humano **aprova** quando o impacto excede o que os manifestos e *playbooks* deixam passar sem *ledger* — mantendo **§11** e **`docs/APPROVALS.md`** como fonte de verdade para classes *steward*.  
- **A4** em superfícies críticas permanece **fora de política**: o OS deve continuar **hostil** a falso verde (§10) e a execução *steward* sem rasto humano.

### 2. O que pode ser 100% autónomo

«**100%**» significa **autonomia de passo** em **A3**: o agente pode avançar **sem** pedir autorização **a cada micro-passo**, desde que cumpra as **condições** abaixo. Continua a ser **quase** total no sentido jurídico-operacional: **§11** aplica-se a *steward* / produção / *release* / migração / destrutivo; revisão de *pull request* segue a política da equipa.

**Estas áreas podem ser autonomizadas quase totalmente:**

- diagnóstico local  
- seleção de perfil de validação  
- leitura seletiva de ficheiros  
- análise de drift  
- sync de artefactos gerados  
- validação de JSON/schemas  
- lint documental  
- atualização de índices  
- geração de exemplos  
- criação de logs JSONL  
- preparação de audit evidence  
- sugestões de remediação  
- criação de playbooks  
- verificação de skills  
- verificação de context budget  
- geração de relatórios  
- correção de inconsistências documentais simples  

**Aqui o agente pode operar sem pedir autorização a cada passo, desde que:**

- trabalhe em branch  
- tenha dry-run quando aplicável  
- gere diff  
- valide depois  
- reporte resultado  
- não toque em segredos  
- não faça ações destrutivas  

*Nota (implementação no repositório):* `os-doctor.ps1`, `os-validate.ps1` / `os-runtime.ps1`, verificadores de *drift* e de documentação, `verify-examples.ps1`, `run-contract-tests.ps1`, `write-validation-history.ps1`, `export-audit-evidence.ps1`, `verify-skills*.ps1`, `verify-context-economy.ps1`, `verify-skills-economy.ps1`, §9 para evidência. *Playbooks* com `requiresApprovalFor` *steward* continuam sujeitos a **§11** antes de execução real; *dry-run* típico: `-WhatIf` em *scripts* com `SupportsShouldProcess`. «Ações destrutivas» inclui *force push*, alterações em produção e passos *Destructive* / *Migration* / *Release* sem *ledger*.

Se alguma condição falhar, a postura desce para **A1**–**A2** até haver evidência e confiança suficientes.

### 3. O que pode ser autónomo com rollback

Pressupõe **diff** revível e caminho de **rollback** (por exemplo *branch* + `git revert` / `git reset`, ou passos documentados). **§11** mantém-se para *steward*, produção e *release* real.

**Estas tarefas podem ser executadas autonomamente se o sistema tiver rollback/diff:**

- formatar Markdown/JSON  
- atualizar README/docs  
- sincronizar skills  
- atualizar generated adapters  
- criar novos manifests  
- adicionar validators  
- criar exemplos  
- corrigir paths quebrados  
- adicionar testes de contrato  
- atualizar runtime profiles  
- gerar changelog local  

**Regra:**

Pode aplicar sozinho se conseguir provar:

1. o que mudou  
2. por que mudou  
3. como validar  
4. como reverter  

*Nota (repositório):* evidência em §9 (*diff*, *commit*, JSON/JSONL); racional em mensagem de *commit*, PR ou *operator journal*; validação com `os-validate`, `verify-os-health`, `run-contract-tests.ps1` conforme o caso; reverso com Git ou plano alinhado a `rollbackPlanReference` (**§11**) em mudanças grandes. *Skills*/*adapters*: verificadores de *drift*; manifestos/*validators*: `script-manifest.json`, `component-manifest.json`, `verify-components.ps1`; exemplos/contratos: `examples/`, `tests/contracts/`; *runtime profiles*: `verify-runtime-profiles.ps1`; *changelog* local vs `docs/UPGRADE.md` ou convenção da equipa.

### 4. O que exige aprovação humana

Mesmo num modelo **~95% autónomo** (§17), estas **superfícies** devem exigir **aprovação humana** explícita — *ledger*, PR com *owners*, ou processo organizacional equivalente. Alinham às classes *steward* em **`docs/APPROVALS.md`** e **`runtime-budget.json`** → `approvalRequiredFor`.

**Superfícies que devem exigir aprovação:**

- produção  
- release oficial  
- alterações destrutivas  
- migrações  
- incident response com impacto real  
- mudanças de segurança  
- alterações a secrets  
- remoção de ficheiros  
- alteração de gates críticos  
- relaxamento de políticas  
- bypass de validações  
- alteração de schemas centrais incompatível  

**Regra profissional:**

O sistema pode **preparar tudo**.  
O humano **aprova a transição de risco**.

**Exemplo:** o Claude OS pode preparar uma **release candidate** completa:

- validar *strict*  
- gerar evidência  
- atualizar docs  
- gerar changelog  
- verificar *drift*  
- preparar *tag proposal*  
- preparar *release notes*  

**Mas** não deve **publicar** a *release* final (promover artefacto, *tag* definitiva, *deploy* a produção) **sem** aprovação humana e registo conforme **§11** / `append-approval-log.ps1` quando a política o exigir.

*Nota:* alterar `quality-gates/`, `runtime-budget.json`, `neverTreatAsPassed`, ou contornar verificadores, é **transição de risco** — tratar como aprovação obrigatória e documentada, não como *commit* silencioso.
