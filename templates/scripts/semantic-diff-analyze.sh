#!/usr/bin/env bash
# Semantic diff analyzer — contracts + refactor/security heuristics (TS Compiler API). H10: LF-only; exit 0.
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  echo "  skip: node not available"
  exit 0
fi

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE=""
if [[ -f "${REPO_ROOT}/.claude/invariant-engine/semantic-diff.cjs" ]]; then
  ENGINE="${REPO_ROOT}/.claude/invariant-engine/semantic-diff.cjs"
elif [[ -f "${REPO_ROOT}/templates/invariant-engine/dist/semantic-diff.cjs" ]]; then
  ENGINE="${REPO_ROOT}/templates/invariant-engine/dist/semantic-diff.cjs"
fi

if [[ -z "$ENGINE" || ! -f "$ENGINE" ]]; then
  echo "  skip: semantic-diff.cjs missing (.claude/invariant-engine/ or templates/invariant-engine/dist/)"
  echo "  hint: cd templates/invariant-engine && npm install && npm run build"
  exit 0
fi

EXTRA=()
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      EXTRA+=("--base" "$2")
      shift 2
      ;;
    --file)
      TARGET="$2"
      shift 2
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "  usage: semantic-diff-analyze.sh [--base REF] --file <path.ts>  |  semantic-diff-analyze.sh <path.ts>"
  exit 0
fi

node "$ENGINE" "$REPO_ROOT" "$TARGET" "${EXTRA[@]}" || true

exit 0
