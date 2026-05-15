# /deploy-check

Verifica problemas de deploy antes de qualquer git push para Railway, Vercel, ou Render.
Corre obrigatoriamente antes do primeiro deploy de qualquer projecto.

## Sequência

### 1. Dockerfile checks
bash .claude/scripts/deploy-check.sh --dockerfile

### 2. Vite config checks
bash .claude/scripts/deploy-check.sh --vite

### 3. Railway config checks
bash .claude/scripts/deploy-check.sh --railway

### 4. Output esperado
[DEPLOY-CHECK] Dockerfile
ok   : FROM node:20-alpine — matches engines.node >=20
ok   : ARG VITE_SUPABASE_URL declared
ok   : ARG VITE_SUPABASE_ANON_KEY declared
FAIL : envsubst missing explicit filter — use envsubst '$PORT' not envsubst
[DEPLOY-CHECK] Vite
ok   : no UI/i18n deps in rollupOptions.external
FAIL : i18next found in external — must be bundled
[DEPLOY-CHECK] Railway
ok   : no startCommand in railway.json (Dockerfile CMD takes precedence)
RESULT: 2 issues found — fix before push

## Regras
- FAIL em qualquer check bloqueia o deploy
- Corre antes de qualquer primeiro deploy
- Corre após qualquer mudança ao Dockerfile, vite.config.ts, ou railway.json
