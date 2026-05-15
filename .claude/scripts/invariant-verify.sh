#!/usr/bin/env bash
# Invariant verification — TypeScript Compiler API (bundled engine). H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-INVARIANT]"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

INV_DIR="${INVARIANTS_DIR:-${REPO_ROOT}/.claude/invariants}"
if [[ ! -d "$INV_DIR" ]]; then
  TINV="${REPO_ROOT}/templates/local/invariants"
  [[ -d "$TINV" ]] && INV_DIR="$TINV"
fi

ENGINE=""
if [[ -f "${REPO_ROOT}/.claude/invariant-engine/invariant-engine.cjs" ]]; then
  ENGINE="${REPO_ROOT}/.claude/invariant-engine/invariant-engine.cjs"
elif [[ -f "${SCRIPT_DIR}/../invariant-engine/invariant-engine.cjs" ]]; then
  ENGINE="$(cd "${SCRIPT_DIR}/../invariant-engine" && pwd)/invariant-engine.cjs"
elif [[ -f "${REPO_ROOT}/templates/invariant-engine/dist/invariant-engine.cjs" ]]; then
  ENGINE="${REPO_ROOT}/templates/invariant-engine/dist/invariant-engine.cjs"
fi

if ! command -v node >/dev/null 2>&1; then
  echo "  skip: node not available"
  exit 0
fi

if [[ -z "$ENGINE" || ! -f "$ENGINE" ]]; then
  echo "  skip: invariant-engine bundle missing (.claude/invariant-engine/invariant-engine.cjs)"
  echo "  hint: bootstrap from OS templates or run: npm run build in templates/invariant-engine"
  exit 0
fi

node "$ENGINE" "$REPO_ROOT" "$INV_DIR" || true

exit 0
