#!/usr/bin/env bash
# Context window allocation estimate from subgraph + policy/session files. exit 0; LF-only.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "[OS-CONTEXT-ALLOCATOR] ERROR: --target <filepath> required"
  exit 0
fi

if [[ -f "${SCRIPTS}/knowledge-graph.sh" ]]; then
  bash "${SCRIPTS}/knowledge-graph.sh" --subgraph "$TARGET" || true
fi

# Approximate tokens: 1 token ≈ 4 chars (rough UTF-8 heuristic; not a real tokenizer).
tok() {
  local n=0
  if [[ -f "$1" ]]; then
    n=$(wc -c <"$1" 2>/dev/null | tr -d " " || echo 0)
  fi
  echo $(( (n + 3) / 4 ))
}

sum_subgraph_code() {
  local sg="$1"
  local total=0
  if [[ ! -f "$sg" ]]; then
    echo 0
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo 0
    return
  fi
  python3 - "$sg" "$REPO_ROOT" <<'PY'
import json, sys
from pathlib import Path
sg = Path(sys.argv[1])
root = Path(sys.argv[2])
total = 0
try:
    data = json.loads(sg.read_text(encoding="utf-8"))
except Exception:
    print(0)
    raise SystemExit
for rel in (data.get("nodes") or {}):
    p = root / rel
    if p.is_file():
        try:
            total += p.stat().st_size
        except OSError:
            pass
print((total + 3) // 4)
PY
}

BASE="$(basename "$TARGET" | sed 's/[^a-zA-Z0-9_.-]/_/g')"
SG="${REPO_ROOT}/.claude/subgraph-${BASE}.json"
GRAPH_CHARS=0
if [[ -f "$SG" ]]; then
  GRAPH_CHARS=$(wc -c <"$SG" 2>/dev/null | tr -d " " || echo 0)
fi
GRAPH_TOK=$(( (GRAPH_CHARS + 3) / 4 ))

CODE_TOK=$(sum_subgraph_code "$SG")

POLICY_TOK=15000

SESS_TOK=0
for f in "${REPO_ROOT}/.claude/session-state.md" "${REPO_ROOT}/.claude/learning-log.md"; do
  t=$(tok "$f")
  SESS_TOK=$((SESS_TOK + t))
done

SUM=$(( CODE_TOK + GRAPH_TOK + POLICY_TOK + SESS_TOK ))
BUDGET=$(( 180000 - SUM ))

echo "[OS-CONTEXT-ALLOCATOR] target: ${TARGET}"
echo "  code (subgraph)   : ~${CODE_TOK} tokens"
echo "  knowledge graph   : ~${GRAPH_TOK} tokens"
echo "  policies          : ~${POLICY_TOK} tokens"
echo "  session context   : ~${SESS_TOK} tokens"
echo "  ─────────────────────────────────"
echo "  operational budget: ~${BUDGET} tokens"
echo ""
echo "  WARNING: if session exceeds 140,000 tokens → trigger /pre-compact"
echo "  SUBGRAPH: ${SG} ready for injection"

if [[ "$BUDGET" -lt 60000 ]]; then
  echo "  WARN: context budget tight — consider splitting session"
fi

exit 0
