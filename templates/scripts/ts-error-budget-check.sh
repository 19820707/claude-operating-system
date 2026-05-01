#!/usr/bin/env bash
# TypeScript error budget — compare current tsc errors to baseline in .local/ts-error-budget.json
# Default: warn only, exit 0.  --enforce  exit 1 on regression (use with OS_STRICT_GATES=1 on session-end).
# H10: LF-only.
set -euo pipefail

ENFORCE=0
for a in "$@"; do
  if [ "$a" = "--enforce" ]; then ENFORCE=1; fi
done

CONFIG=".local/ts-error-budget.json"
if [ ! -f "$CONFIG" ]; then
  exit 0
fi

if [ ! -f tsconfig.json ] && [ ! -f tsconfig.base.json ]; then
  echo "[TS-BUDGET] skip (no tsconfig)"
  exit 0
fi

BASELINE=$(grep -o '"baselineErrors"[[:space:]]*:[[:space:]]*[-0-9]*' "$CONFIG" 2>/dev/null | grep -oE '-?[0-9]+$' | head -1)
if [ -z "$BASELINE" ]; then
  BASELINE=-1
fi

if [ "$BASELINE" -lt 0 ]; then
  echo "[TS-BUDGET] baseline unset (baselineErrors=-1). Run: bash .claude/scripts/ts-error-budget-init.sh"
  exit 0
fi

CMD=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" | head -1)
if [ -z "$CMD" ]; then
  CMD="npx tsc --noEmit --pretty false"
fi

set +e
OUT=$(eval "$CMD" 2>&1)
RC=$?
set -e
COUNT=$(echo "$OUT" | grep -c "error TS" || true)

echo "[TS-BUDGET] baseline=${BASELINE} current=${COUNT} (tsc exit=${RC})"

if [ "$COUNT" -gt "$BASELINE" ]; then
  echo "[TS-BUDGET] REGRESSION: ${COUNT} > ${BASELINE} — fix types, raise baseline intentionally, or document exception in learning-log"
  if [ "$ENFORCE" -eq 1 ]; then
    exit 1
  fi
elif [ "$COUNT" -lt "$BASELINE" ]; then
  echo "[TS-BUDGET] improved vs baseline (${COUNT} < ${BASELINE}) — consider ts-error-budget-init.sh to ratchet baseline down"
fi

exit 0
