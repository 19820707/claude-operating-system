#!/usr/bin/env bash
# OS pre-flight — SessionStart orchestration (non-blocking). H10: LF-only; exit 0 always.
set -euo pipefail

SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)

echo "[OS-PREFLIGHT]"

BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
HEAD=$(git log -1 --format="%h %s" 2>/dev/null || echo unknown)
WT=$(git status --short 2>/dev/null | wc -l | tr -d " ")
STATE_AGE=$(git log -1 --format="%cr" -- .claude/session-state.md 2>/dev/null || echo unknown)
SECRETS=$(git ls-files 2>/dev/null | grep -E "\.env$|\.env\.[^.]+$|\.pem$|\.key$|settings\.local\.json$" | head -3 || true)

echo "  branch : ${BRANCH}"
echo "  head   : ${HEAD}"
echo "  wt     : ${WT} files"
echo "  state  : session-state.md ${STATE_AGE}"

if [ -n "${SECRETS}" ]; then
  echo "  WARN   : secrets tracked -> ${SECRETS}"
fi

if [ -f ".claude/wt-snapshot.tmp" ]; then
  PREV_WT=$(grep "^wt_count=" .claude/wt-snapshot.tmp | cut -d= -f2 || echo 0)
  PREV_TS=$(grep "^ts=" .claude/wt-snapshot.tmp | cut -d= -f2 || echo unknown)
  if [ "${PREV_WT}" -gt 0 ]; then
    echo "  WARN   : previous session (${PREV_TS}) ended with ${PREV_WT} uncommitted files"
  fi
fi

if [ -f "${SCRIPTS_DIR}/drift-detect.sh" ]; then
  bash "${SCRIPTS_DIR}/drift-detect.sh" || true
fi
echo ""

if [ -f "${SCRIPTS_DIR}/agent-coordinator.sh" ]; then
  bash "${SCRIPTS_DIR}/agent-coordinator.sh" --expire || true
  bash "${SCRIPTS_DIR}/agent-coordinator.sh" --status || true
fi
echo ""

if [ -f "${SCRIPTS_DIR}/heuristic-ratchet.sh" ]; then
  bash "${SCRIPTS_DIR}/heuristic-ratchet.sh" || true
fi
if [ -f "${SCRIPTS_DIR}/ts-error-budget.sh" ]; then
  bash "${SCRIPTS_DIR}/ts-error-budget.sh" || true
fi
echo ""

if [ -f "${SCRIPTS_DIR}/invariant-engine.sh" ]; then
  bash "${SCRIPTS_DIR}/invariant-engine.sh" --staleness || true
fi
echo ""

if [ -f "${SCRIPTS_DIR}/risk-surface-scan.sh" ]; then
  bash "${SCRIPTS_DIR}/risk-surface-scan.sh" || true
fi
echo ""

if [ -f "${SCRIPTS_DIR}/policy-compliance.sh" ]; then
  bash "${SCRIPTS_DIR}/policy-compliance.sh" --session "${BRANCH}" || true
fi
echo ""

if [ -f "${SCRIPTS_DIR}/os-telemetry.sh" ]; then
  bash "${SCRIPTS_DIR}/os-telemetry.sh" || true
fi

exit 0
