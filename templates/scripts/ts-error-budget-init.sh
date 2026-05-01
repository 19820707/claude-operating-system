#!/usr/bin/env bash
# TypeScript error budget — capture current tsc error count as baseline in .local/ts-error-budget.json
# Run once per repo (or after intentional error-budget reset). H10: LF-only.
set -euo pipefail

CONFIG=".local/ts-error-budget.json"
if [ ! -f "$CONFIG" ]; then
  echo "[TS-BUDGET] missing ${CONFIG} — copy from OS template or run init-project.ps1"
  exit 1
fi

if [ ! -f tsconfig.json ] && [ ! -f tsconfig.base.json ]; then
  echo "[TS-BUDGET] skip init (no tsconfig.json / tsconfig.base.json)"
  exit 0
fi

CMD=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -1)
if [ -z "$CMD" ]; then
  CMD="npx tsc --noEmit --pretty false"
fi

echo "[TS-BUDGET] running: ${CMD}"
set +e
OUT=$(eval "$CMD" 2>&1)
RC=$?
set -e
COUNT=$(echo "$OUT" | grep -c "error TS" || true)
echo "[TS-BUDGET] tsc exit=${RC} counted_errors=${COUNT}"

TMP=$(mktemp)
sed "s/\"baselineErrors\":[[:space:]]*[-0-9]*/\"baselineErrors\": ${COUNT}/" "$CONFIG" > "$TMP"
mv "$TMP" "$CONFIG"

echo "[TS-BUDGET] baselineErrors updated to ${COUNT} in ${CONFIG}"
exit 0
