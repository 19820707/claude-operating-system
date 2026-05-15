# Stack profile: React 18 + Vite + TypeScript + Tailwind

SPA / frontend operacional. Referência em `.claude/stack-profile.md` (`init-project.ps1 -Profile react-vite-app`).

---

## Model defaults by task type

| Task | Model | Mode |
|------|-------|------|
| Read / grep / bundle triage | Haiku | Explore |
| Component / hook / local state | Sonnet | Build |
| Refactor (UI patterns, non-auth) | Sonnet | Build |
| Auth UI / session storage | Opus | Critical |
| Payment / checkout UI | Opus | Critical |
| Routing / access control | Opus | Critical |
| Analytics touching PII | Opus | Critical |
| Release / deploy | Opus | Release |

---

## Critical surfaces (Opus mandatory)

- `**/auth/**`
- `**/login/**`
- `**/checkout/**`
- `**/billing/**`
- `**/analytics/**`
- `**/*RouteGuard***`
- `**/sw.*`
- `**/service-worker***`

---

## Validation commands

- `npx tsc --noEmit`
- `npx vitest run`
- `npx playwright test`
- `npx eslint .`
- `npm run build`
- `npm run check:seo` *(se existir no package.json)*

---

## Hook permissions (`settings.json` additions)

Same baseline as Node profile: `npx tsc`, `eslint`, `vitest`, `playwright`, `npm run build`, and `bash .claude/scripts/*` hooks.

---

## Pre-session checklist

1. Drift + TS budget verdes (hooks / scripts manuais).
2. Rotas com dados sensíveis — query params sem PII?
3. Guards de rota alinhados com backend (sem bypass paralelo).
4. Build de produção (`npm run build`) sem warnings críticos de segurança.

---

## Common failure modes

| Failure | Diagnosis | Fix |
|---------|-----------|-----|
| PII in URL params / referrer | Logging e analytics | Redact; mover identificadores para POST/body seguro |
| Auth bypass via parallel guard | H9 | Um único caminho de autorização; E2E nos dois fluxos |
| Build ok / runtime crash | import dinâmico, env runtime | Testar `vite preview` + sourcemaps |
| E2E flaky on CI | timing, selectors | `data-testid`, retries orçados, isolamento de rede |
| SW caches stale auth | service worker | Versionar cache; logout limpa caches sensíveis |

---

## Architecture invariants

1. **Client never trusts the UI** — validação server-side obrigatória para regras de negócio.
2. **Tokens** só em httpOnly / fluxos documentados; não em `localStorage` para sessões sensíveis.
3. **Code splitting** não expõe rotas admin sem lazy + guard.
4. **A11y + SEO** críticos para páginas públicas; regressões tratadas como bugs P1.
5. **CSP e headers** alinhados com integrações (scripts terceiros documentados).

---

## Railway + Docker deployment

- Dockerfile deve usar `node:20-alpine` ou superior
- VITE_* vars: declarar `ARG VITE_X` + `ENV VITE_X=$VITE_X` antes do `RUN pnpm build` — definir apenas no Railway não é suficiente (H11)
- nginx: usar `envsubst '$PORT'` com single quotes para evitar corrupção de variáveis nginx (H12)
- `railway.json`: não declarar `startCommand` quando o Dockerfile já tem `CMD`
- `pnpm-lock.yaml`: usar `--frozen-lockfile` no CI
