#!/usr/bin/env bash
# OS pre-flight — runs once per session via SessionStart hook.
# Checks git state, session-state staleness, ratchet baseline, previous WT, secrets.
# H10: LF-only; exit 0 always (non-blocking).
set -euo pipefail

BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
HEAD=$(git log -1 --format="%h %s" 2>/dev/null || echo unknown)
WT=$(git status --short 2>/dev/null | wc -l | tr -d " ")
STATE_AGE=$(git log -1 --format="%cr" -- .claude/session-state.md 2>/dev/null || echo unknown)
SECRETS=$(git ls-files 2>/dev/null | grep -E "\.env$|\.env\.[^.]+$|\.pem$|\.key$|settings\.local\.json$" | head -3 || true)

echo "[OS-PREFLIGHT]"
echo "  branch : ${BRANCH}"
echo "  head   : ${HEAD}"
echo "  wt     : ${WT} files"
echo "  state  : session-state.md ${STATE_AGE}"

# Ratchet baseline check (project-specific — skip if not used)
if [ -f ".local/ts-error-budget.json" ] || [ -d ".local" ]; then
  if [ ! -f ".local/ts-error-budget.json" ]; then
    echo "  WARN   : ratchet baseline missing (.local/ts-error-budget.json)"
  fi
fi

# Previous session dirty WT warning
if [ -f ".claude/wt-snapshot.tmp" ]; then
  PREV_WT=$(grep "^wt_count=" .claude/wt-snapshot.tmp | cut -d= -f2 || echo 0)
  PREV_TS=$(grep "^ts=" .claude/wt-snapshot.tmp | cut -d= -f2 || echo unknown)
  if [ "${PREV_WT}" -gt 0 ]; then
    echo "  WARN   : previous session (${PREV_TS}) ended with ${PREV_WT} uncommitted files"
  fi
fi

if [ -n "${SECRETS}" ]; then
  echo "  WARN   : secrets tracked -> ${SECRETS}"
fi

# Context drift (session-state vs git) — warn-only here; strict on session-end if OS_STRICT_GATES=1
if [ -f ".claude/scripts/context-drift-detect.sh" ]; then
  bash .claude/scripts/context-drift-detect.sh 2>/dev/null || true
fi

# TypeScript error budget — warn-only; baseline via ts-error-budget-init.sh
if [ -f ".claude/scripts/ts-error-budget-check.sh" ]; then
  bash .claude/scripts/ts-error-budget-check.sh 2>/dev/null || true
fi
