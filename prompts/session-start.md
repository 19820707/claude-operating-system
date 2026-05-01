Le primeiro (por esta ordem — obrigatorio):
1. CLAUDE.md
2. .claude/session-state.md  <- baseline de continuidade operacional; usa como ponto de partida
3. .claude/policies/engineering-governance.md
4. .claude/policies/production-safety.md

Depois executa por esta ordem:
1. verificar branch e ultimo commit em session-state.md (e reconciliar com o output do hook preflight: blocos `[CONTEXT-DRIFT]` e `[TS-BUDGET]` quando existirem);
2. mapear a arquitetura real do repositorio;
3. identificar os fluxos criticos;
4. identificar os 10 maiores riscos estruturais, operacionais e de seguranca;
5. propor roadmap faseado;
6. escolher a melhoria de maior valor e menor risco;
7. implementar de forma incremental;
8. validar;
9. actualizar .claude/session-state.md no fecho da sessao;
10. resumir impacto, risco residual e rollback.

Nao responder de forma generica.
Basear todas as conclusoes em evidencia do repositorio.
Nao inventar estado sem evidencia — session-state.md e a fonte de verdade.