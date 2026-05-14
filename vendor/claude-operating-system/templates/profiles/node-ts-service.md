# Stack profile: Node.js + TypeScript + Express/Fastify + PostgreSQL

Use as operational defaults for services and APIs. Copy reference: `.claude/stack-profile.md` (from `init-project.ps1 -Profile node-ts-service`).

---

## Model defaults by task type

| Task | Model | Mode |
|------|-------|------|
| Read / grep / triage | Haiku | Explore |
| Endpoint / middleware / wiring | Sonnet | Build |
| Refactor (non-critical paths) | Sonnet | Build |
| Auth / entitlement / session | Opus | Critical |
| Migrations / schema | Opus | Migration |
| Payments / webhooks / billing | Opus | Critical |
| Release / deploy gate | Opus | Release |
| Production incident | Opus | Incident |

---

## Critical surfaces (Opus mandatory)

- `**/auth/**`
- `**/integrations/payments/**`
- `**/migrations/**`
- `**/*entitlement***`
- `**/*tierGat***`
- `**/*publish***`
- `**/*pii***`

---

## Validation commands

Run before merge / release candidate:

- `npx tsc --noEmit`
- `npx vitest run`
- `npx playwright test`
- `npx eslint .`
- `npm run build`

---

## Hook permissions (`settings.json` additions)

Ensure `allow` includes at least:

- `Bash(npx tsc *)` / `Bash(npx tsc --noEmit)`
- `Bash(npx vitest run *)`
- `Bash(npx playwright test *)`
- `Bash(npx eslint *)`
- `Bash(npm run build *)`
- `Bash(bash .claude/scripts/preflight.sh)` and other `.claude/scripts/*` used by hooks

---

## Pre-session checklist

1. `bash .claude/scripts/drift-detect.sh` — `session-state` alinhado com `git`?
2. `bash .claude/scripts/ts-error-budget.sh` — orçamento TS dentro do baseline?
3. Rotas novas com auth / rate-limit / validação de input?
4. Migrações: additive + rollback script ou plano documentado?

---

## Common failure modes

| Failure | Diagnosis | Fix |
|---------|-----------|-----|
| Stash / checkout polui centenas de ficheiros (Windows CRLF) | H1 — line endings normalised por editor | Normalizar LF, `git add` selectivo, evitar stash de artefactos gerados |
| Silent auth bypass (parallel guard) | H9 — dois caminhos para a mesma acção | Um único gate; testes de integração no caminho “feliz” e no alternativo |
| Boundary off-by-one (inclusive vs exclusive) | H6 — intervalos / paging | Revisar contrato API + testes de limite |
| Entitlement fail-open | H8 — default permissivo | Fail-closed; métricas + logs em negação |
| `.sh` hooks com CRLF | H10 — hooks quebram em Linux/CI | `dos2unix` ou editor em LF-only |

---

## Architecture invariants

1. **AuthZ follows authN** — não expor acções sem sujeito autenticado resolvido.
2. **Idempotency** em webhooks e jobs mutadores (chaves naturais ou idempotency keys).
3. **Migrations** só additive em trunk; destructive só com fase explícita + backup.
4. **PII** minimizado em logs; nunca secrets em queries ou URLs.
5. **Timeouts + cancelamento** em chamadas externas (DB, HTTP, queues).
6. **Feature flags / kill switches** para integrações de pagamento e envio de e-mail em incidentes.
