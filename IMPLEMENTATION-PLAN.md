Tens acesso ao repositório claude-operating-system.
És um principal systems engineer e architect de sistemas críticos.

Implementa as seguintes 6 capacidades de engenharia de sistemas avançada.
Cada uma resolve um problema de classe diferente. Nenhuma é um script bash com grep.
Todas têm testes, tratamento de erros robusto, e integração com o CI existente.
Commit único no fim com mensagem semântica precisa.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
I. DECISION AUDIT ENGINE (tools/decision-audit-engine.ps1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problema resolvido: não há forma de auditar se as políticas foram seguidas numa sessão.

Arquitectura:
- Lê .claude/decision-log.jsonl (append-only, escrito pelo decision-audit.sh)
- Para cada decisão de type=model_selection: verifica se o modelo escolhido é consistente com a política em .claude/policies/model-selection.md
  Regra: se trigger menciona qualquer padrão de auth|billing|migration|payment|secret → model deve ser Opus
  Regra: se confidence=LOW sem pelo menos 2 evidence items → flag como WEAK_EVIDENCE
- Para cada decisão de type=scope_boundary: verifica se scope_expansion tinha autorização explícita
- Calcula compliance_rate = decisions_compliant / decisions_total
- Detecta drift de política: se compliance_rate desta sessão < compliance_rate média das últimas 5 sessões → POLICY_DRIFT detectado
- Output JSON:
  { "session": "...", "compliance_rate": 0.91, "violations": [...], "weak_evidence": [...], "policy_drift": bool, "trend": "improving|stable|degrading" }
- Modo --session <id>: audita sessão específica
- Modo --trend: mostra evolução de compliance ao longo do tempo via decision-log.jsonl histórico
- Integração: adicionar como step em os-validate.ps1 Profile strict
- exit 0 sempre (não bloqueia — reporta)
- LF-only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
II. PROBABILISTIC RISK CALIBRATOR (tools/risk-calibrator.ps1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problema resolvido: risco é categórico (LOW/MEDIUM/HIGH/CRITICAL) baseado em opinião estática. Não reflecte histórico real.

Arquitectura:
- Para cada ficheiro passado como argumento (--files a.ps1,b.ps1):
  CHURN (90 dias): git log --oneline --since="90 days ago" --follow -- <file> | wc -l
  BUG_DENSITY: git log --oneline --follow --grep="fix|bug|hotfix|revert|incident" -- <file> | wc -l
  INCIDENT_PROXIMITY: git log --oneline --grep="incident|emergency|sev[0-9]|hotfix" -- <file> | wc -l
  AUTHOR_COUNT: git log --format="%ae" --follow -- <file> | Sort-Object -Unique | Measure-Object | Select-Object -ExpandProperty Count
  
- Calcula P(incident) por ficheiro:
  base = BUG_DENSITY / max(CHURN, 1)
  adjusted = base * (1 + INCIDENT_PROXIMITY * 0.5) * (1 + (AUTHOR_COUNT - 1) * 0.1)
  P(incident) = [0.0, 1.0] capped
  
- Calcula BLAST_RADIUS via script-graph.json (já existe):
  direct_dependents = edges onde "to" == ficheiro
  transitive = DFS depth=2 sobre o grafo
  blast_score = direct * 1.0 + transitive * 0.3

- Risk score composto:
  score = P(incident) * 0.6 + blast_score_normalised * 0.4
  level: score >= 0.7 → CRITICAL, 0.5-0.69 → ELEVATED, 0.3-0.49 → MODERATE, < 0.3 → LOW

- Output JSON por ficheiro:
  { "file": "...", "p_incident": 0.34, "blast_radius": { "direct": 3, "transitive": 8 }, "risk_score": 0.61, "level": "ELEVATED", "calibration": "based on N changes (90d)" }

- Modo --scan: analisa todos os ficheiros modificados no WT actual (git diff --name-only)
- Modo --threshold <score>: exit 1 se qualquer ficheiro acima do threshold (para pre-push gate)
- Escreve .claude/risk-profile.json com resultados
- Integração: adicionar ao pre-push hook — se score > 0.7 → warn antes de push
- exit 0 por defeito, exit 1 só com --threshold excedido
- LF-only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
III. SEMANTIC KNOWLEDGE GRAPH ENGINE (tools/knowledge-graph-engine.ps1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problema resolvido: heurísticas são texto não-queryável. Não há forma de perguntar "que heurísticas são relevantes para este ficheiro neste contexto?"

Arquitectura:
- Lê heuristics/operational.md e extrai estrutura de cada heurística:
  ID, nome, evidence, rule, apply, ficheiros mencionados (grep de paths), padrões mencionados (Docker, nginx, PowerShell, etc.)
  
- Constrói grafo semântico em .claude/knowledge-graph.json:
  Nós: { id: "H11", type: "heuristic", tags: ["docker", "vite", "env"], files: ["Dockerfile", "vite.config.ts"], confidence: 1.0 }
  Edges: { from: "H11", to: "H12", type: "co-occurs", weight: 0.8 } (heurísticas que aparecem juntas em sessões)

- Modo --query <context>: dado um contexto (ficheiro ou lista de tags), devolve heurísticas relevantes ordenadas por relevância
  Relevância = overlap de tags + overlap de ficheiros mencionados + co-occurrence weight
  Output: top-5 heurísticas mais relevantes para o contexto, com score
  
- Modo --build: reconstrói o grafo completo de heuristics/operational.md
  
- Modo --enrich: lê decision-log.jsonl, detecta quais heurísticas foram mencionadas em decisões, actualiza co-occurrence weights
  
- Modo --export-context <files>: exporta subgrafo relevante para um conjunto de ficheiros em formato injectável no contexto do Claude
  Output: bloco markdown compacto com as heurísticas mais relevantes para aqueles ficheiros

- Integração: o preflight.sh chama --export-context com os ficheiros do WT actual → resultado injectado no session-start
- exit 0 sempre
- LF-only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IV. OUTCOME-DRIVEN LEARNING ENGINE (tools/outcome-learning.ps1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problema resolvido: o sistema aprende padrões mas não actualiza o modelo de risco com outcomes reais. Um ficheiro que causou 3 incidentes devia ter P(incident) maior — automaticamente.

Arquitectura:
- Lê .claude/decision-log.jsonl para decisões históricas
- Lê git log para outcomes: commits com "fix", "revert", "incident" após commits que tocaram os mesmos ficheiros
- Correlação causal:
  Para cada ficheiro: conta quantas vezes foi modificado e quantas vezes houve um "fix" commit nos 7 dias seguintes
  P(incident|file) = fix_commits_after / total_modifications — actualiza risk-calibrator baseline
  
- Detecta padrões de co-failure:
  Se ficheiros A e B são modificados juntos e seguidos de fix com frequência > 0.3 → registar como coupled_risk
  
- Actualiza .claude/learned-baselines.json:
  { "file_risk_overrides": { "tools/verify-agent-adapters.ps1": 0.45 }, "coupled_risks": [["A.ps1", "B.ps1"]], "last_calibrated": "..." }
  
- Modo --calibrate: corre análise completa e actualiza baselines
- Modo --report: mostra ficheiros com maior P(incident) aprendido vs baseline estático
- Modo --promote-heuristic: quando padrão de co-failure tem confidence >= 0.7 e N >= 5 observações → propõe nova entrada em heuristics/operational.md com evidência quantitativa

- Integração: risk-calibrator.ps1 lê learned-baselines.json como override do baseline estático
- Corre automaticamente via SessionEnd hook
- exit 0 sempre
- LF-only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
V. CROSS-PROJECT INTELLIGENCE FABRIC (tools/intelligence-fabric.ps1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problema resolvido: cada projecto aprende isolado. Os erros do centro-hub não beneficiam automaticamente o rallyo-platform no arranque.

Arquitectura:
- Mantém heuristics/cross-project-evidence.json como repositório central de padrões cross-projecto:
  { "patterns": { "docker-vite-env": { "confirmed_in": ["centro-hub"], "total": 1, "p_recurrence": 0.8, "risk_if_ignored": "HIGH", "heuristic_ref": "H11" } } }

- Modo --contribute <project-path>:
  Lê .claude/learned-baselines.json do projecto
  Lê .claude/decision-log.jsonl do projecto
  Extrai: ficheiros de alto risco aprendidos, padrões de co-failure, heurísticas aplicadas com sucesso
  Merge em cross-project-evidence.json com weighted average (projectos mais recentes têm peso maior)
  
- Modo --inherit <project-path>:
  Lê cross-project-evidence.json
  Para cada padrão com total >= 2 projectos:
    Se o projecto tem ficheiros que correspondem ao padrão → injiecta aviso em .claude/session-state.md
    Se heuristic_ref existe → verifica se heurística já está em .claude/heuristics/
  Output: "Inherited N patterns from cross-project intelligence"
  
- Modo --risk-brief <project-path>:
  Dado um projecto novo, analisa o seu stack (package.json, Dockerfile, requirements.txt)
  Cruza com padrões cross-projecto por stack type
  Gera .claude/inherited-risk-brief.md — documento de onboarding com riscos conhecidos para este stack
  
- Modo --sync-all <os-repo-path>:
  Descobre todos os projectos com .claude/ em subdirectorias do os-repo-path parent
  Corre --contribute em todos
  Actualiza cross-project-evidence.json
  
- Integração: init-project.ps1 chama --inherit automaticamente no bootstrap
- Integração: session-digest.ps1 chama --contribute automaticamente no session-end com outcome=passed
- exit 0 sempre
- LF-only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VI. PREDICTIVE INTERVENTION SYSTEM (tools/predictive-intervention.ps1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problema resolvido: o sistema detecta problemas quando acontecem. Este sistema prevê problemas antes de acontecerem e intervém antes do push.

Arquitectura:
- Corre no pre-push hook ANTES do risk-calibrator
- Lê: git diff --name-only (ficheiros a ser pushados), script-graph.json, learned-baselines.json, cross-project-evidence.json, invariants/core.json

- PREDIÇÃO 1 — Invariant Impact:
  Para cada ficheiro no diff: verifica quais invariantes referenciam esse ficheiro ou módulo
  Para cada invariante AT_RISK: calcula probabilidade de violação baseada em histórico de mudanças similares
  Output: "INV-001 at risk (P=0.67) — 4 of 6 previous changes to server/auth violated this invariant"

- PREDIÇÃO 2 — Regression Probability:
  Para cada ficheiro: P(regression) = P(incident|file) * blast_radius_score
  Se P(regression) > 0.5 → "HIGH regression risk — consider splitting this change"

- PREDIÇÃO 3 — Test Coverage Gap:
  Para cada ficheiro modificado: verifica se existe ficheiro de teste correspondente (*.test.*, *.spec.*)
  Se não existe e P(incident|file) > 0.3 → "COVERAGE GAP — no tests for high-risk file"

- PREDIÇÃO 4 — Cross-Project Pattern Match:
  Cruza ficheiros no diff com cross-project-evidence.json
  Se padrão reconhecido → "KNOWN PATTERN: docker-vite-env detected in Dockerfile — see H11"

- OUTPUT CONSOLIDADO antes do push:
  [OS-INTERVENTION] pre-push analysis
  files: 3 | risk: ELEVATED | intervention: ADVISORY
  
  PREDICTIONS:
    INV-001 at risk (P=0.67) — auth boundary may be violated
    H11 pattern detected — verify ARG/ENV in Dockerfile
  
  RECOMMENDATIONS:
    1. Run /verify-invariants before merge
    2. Check Dockerfile ARG declarations (H11)
  
  DECISION: PROCEED with warnings (score: 0.61 < 0.70 threshold)
  [push continuing]

- Se score > 0.85 → exit 1 (bloqueia push) com mensagem clara e comando de override
- Se score 0.70-0.85 → exit 0 com WARNING prominente
- Se score < 0.70 → exit 0 silencioso
- Override: CLAUDE_OS_FORCE_PUSH=1 git push (documenta o override em decision-log.jsonl)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INTEGRAÇÕES GLOBAIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Criar .git/hooks/pre-push:
#!/bin/sh
pwsh -NoProfile -File tools/predictive-intervention.ps1
exit $?

2. Actualizar tools/verify-os-health.ps1:
Adicionar health step "decision-audit" que chama decision-audit-engine.ps1

3. Actualizar tools/os-validate.ps1 Profile strict:
Adicionar: risk-calibrator --scan, knowledge-graph-engine --build, decision-audit-engine

4. Actualizar tools/session-digest.ps1 (já existe em tools/):
Após digest: chamar outcome-learning.ps1 --calibrate e intelligence-fabric.ps1 --contribute

5. Actualizar init-project.ps1:
Após bootstrap: chamar intelligence-fabric.ps1 --inherit e --risk-brief

6. Actualizar bootstrap-manifest.json e script-manifest.json:
Adicionar os 6 novos tools com exact counts correctos

7. Actualizar INDEX.md:
Adicionar secção "Intelligence Layer" com os 6 tools documentados

8. Actualizar .gitignore:
Adicionar: /risk-profile.json, /learned-baselines.json, /failure-patterns.json, /.claude/knowledge-graph.json

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COMMIT FINAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

git add -A
git commit -m "feat(intelligence): decision audit engine, probabilistic risk calibrator, semantic knowledge graph, outcome learning, cross-project fabric, predictive intervention system"
git push origin main
