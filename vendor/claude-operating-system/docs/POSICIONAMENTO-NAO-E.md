# O que o Claude OS não deve ser

Documento de **limites explícitos** do runtime. Complementa a versão em inglês em [`ARCHITECTURE.md`](../ARCHITECTURE.md#what-claude-os-is-not).

**Capacidades e fluxo operacional:** [`CAPACIDADES-OPERACIONAIS.md`](CAPACIDADES-OPERACIONAIS.md).

---

## 2.1 Não é um CI/CD completo

O Claude OS não deve competir com pipelines de CI/CD. Ele não substitui stages formais de build, test, deploy, rollback, ambientes, artefactos, secrets, promotion ou release automation.

A sua função é agir **antes e ao lado** do CI/CD:

pré-validação local  
→ preparação de evidência  
→ verificação de contratos  
→ deteção de drift  
→ execução de playbooks  
→ redução de erro humano/agente  
→ entrega de mudanças mais limpas ao CI/CD  

O CI/CD continua a ser a **autoridade final** para build, test e deployment.

---

## 2.2 Não é substituto de GitHub Actions

GitHub Actions continua a ser o executor remoto e reprodutível em ambiente controlado. O Claude OS deve gerar comandos, perfis e evidências que possam ser usados por GitHub Actions, mas **não** deve substituir a execução independente do pipeline.

A melhoria correta é:

- **Claude OS** define contratos e comandos  
- **GitHub Actions** executa esses contratos em CI  

Exemplo:

```powershell
pwsh ./tools/os-validate.ps1 -Profile strict -Json
```

Este comando pode ser executado localmente, mas o resultado de confiança deve ser **confirmado em CI**.

---

## 2.3 Não é substituto de revisão humana

O Claude OS pode reduzir ruído, preparar diffs, validar contratos, detetar inconsistências e gerar evidência. Mas **não** substitui julgamento de engenharia.

Em superfícies críticas, o sistema deve exigir:

- aprovação humana  
- escopo explícito  
- plano de rollback  
- evidência prévia  
- validação posterior  
- risco residual declarado  

O papel do humano **não** é eliminado; é **elevado**. O humano deixa de rever caos bruto e passa a rever uma mudança estruturada, validada e acompanhada de evidência.

---

## 2.4 Não é uma plataforma SaaS

O Claude OS deve continuar **local-first**, versionável e auditável. Transformá-lo numa plataforma SaaS deslocaria o foco para autenticação, tenancy, billing, disponibilidade e gestão remota, que **não** são o problema central deste projeto.

O valor do Claude OS está em ser:

- portável  
- local  
- determinístico  
- versionado  
- auditável  
- independente de fornecedor  
- adaptável por projeto  

---

## 2.5 Não é sistema autónomo de produção

O Claude OS não deve executar mudanças críticas em produção por autonomia própria.

A sua competência é **preparar, validar e conter** ações. Para Production, Critical, Incident, Migration, Release ou Destructive, o sistema deve operar em modo **gated**:

- sem aprovação humana → sem ação crítica  
- sem evidência → sem release  
- sem rollback → sem mudança sensível  
- sem validação → sem green  

---

## 2.6 Não é agente sem supervisão em mudanças críticas

O Claude OS deve impedir precisamente esse modo de falha. A autonomia em engenharia crítica precisa de limites. O sistema deve assumir que agentes podem:

- interpretar mal contexto  
- sobreconfiar em validações parciais  
- executar mudanças demasiado amplas  
- confundir warning com sucesso  
- ignorar riscos de rollback  
- introduzir drift documental  

Portanto, a função do Claude OS é criar **contenção técnica e processual**.
