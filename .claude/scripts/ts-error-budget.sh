#!/usr/bin/env bash
# TypeScript error budget — baseline in .local/ts-error-budget.json. H10: LF-only.
set -euo pipefail

echo "[OS-TS-BUDGET]"

CONFIG=".local/ts-error-budget.json"
ENFORCE=0
RESET=0
for a in "$@"; do
  case "$a" in
    --enforce) ENFORCE=1 ;;
    --reset) RESET=1 ;;
  esac
done

if [ ! -f tsconfig.json ] && [ ! -f tsconfig.base.json ]; then
  echo "  skip: no tsconfig*.json"
  exit 0
fi

mkdir -p .local

write_json() {
  local b="$1" ts="$2" rb="$3"
  rb="${rb//\\/\\\\}"
  rb="${rb//\"/\\\"}"
  printf '{"schemaVersion":1,"baseline":%s,"ts":"%s","reset_by":"%s"}\n' "$b" "$ts" "$rb" > "$CONFIG"
}

if [ ! -f "$CONFIG" ]; then
  write_json -1 "" ""
fi

read_baseline() {
  grep -o '"baseline"[[:space:]]*:[[:space:]]*-\{0,1\}[0-9]\{1,\}' "$CONFIG" 2>/dev/null | grep -oE '-?[0-9]+$' | head -1 || echo -1
}

COUNT=$( (npx tsc --noEmit 2>&1 || true) | grep -cE "error TS[0-9]+" || true)
COUNT=${COUNT:-0}
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)

if [ "$RESET" -eq 1 ]; then
  write_json "$COUNT" "$TS" "reset:${USER:-unknown}"
  echo "ok: baseline reset to ${COUNT}"
  exit 0
fi

BASE=$(read_baseline)
BASE=${BASE:--1}

if [ "$BASE" -lt 0 ] 2>/dev/null; then
  write_json "$COUNT" "$TS" "auto-init"
  echo "ok: auto-init baseline=${COUNT}"
  exit 0
fi

DELTA=$((COUNT - BASE))
if [ "$COUNT" -gt "$BASE" ]; then
  echo "RATCHET: REGRESSION baseline=${BASE} current=${COUNT} delta=+${DELTA} ACTION=fix types or --reset after intentional change"
  if [ "$ENFORCE" -eq 1 ]; then
    exit 1
  fi
  exit 0
fi

if [ "$COUNT" -lt "$BASE" ]; then
  write_json "$COUNT" "$TS" "auto-improved"
  echo "ok: improved ${BASE} -> ${COUNT} (baseline updated)"
  exit 0
fi

echo "ok: stable (${COUNT})"
exit 0
