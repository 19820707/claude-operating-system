#!/usr/bin/env bash
# OS pre-compact — generates compact session summary before context compaction.
# Extracts phase, objective, next steps from .claude/session-state.md so PostCompact
# can re-inject real continuity context (not just git state).
# H10: LF-only. Exit 0 always (non-blocking).
set -euo pipefail

BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
HEAD=$(git log -1 --format="%h %s" 2>/dev/null || echo unknown)
WT=$(git status --short 2>/dev/null | wc -l | tr -d " ")
TS=$(date -u +"%Y-%m-%dT%H:%MZ" 2>/dev/null || echo unknown)

PHASE="N/A"; OBJ="N/A"; NEXT="N/A"; RISKS="none"; HUMAN_GATE="none"

if [ -f ".claude/session-state.md" ]; then
  PHASE=$(awk '/^## Fase atual|^## Fase actual|^## Current Phase/{f=1;next}/^## /{f=0}f&&/[^[:space:]]/{print;exit}' \
    .claude/session-state.md 2>/dev/null | sed 's/\*\*//g' | cut -c1-150 || echo "N/A")
  OBJ=$(awk '/^## Objectivo|^## Objetivo|^## Objective|^## Current Objective/{f=1;next}/^## /{f=0}f&&/[^[:space:]]/{print;exit}' \
    .claude/session-state.md 2>/dev/null | sed 's/\*\*//g' | cut -c1-150 || echo "N/A")
  NEXT=$(awk '/^## Pr|^## Next/{f=1;next}/^## /{f=0}f&&/^[0-9]+\./{print}' \
    .claude/session-state.md 2>/dev/null | head -3 | tr '\n' ' ' | cut -c1-200 || echo "N/A")
  RISKS=$(awk '/^## Riscos|^## Risks/{f=1;next}/^## /{f=0}f&&/^\|[^-]/{print}' \
    .claude/session-state.md 2>/dev/null | head -3 | tr '\n' '; ' | cut -c1-200 || echo "none")
  if grep -qi "human approval required.*yes" .claude/session-state.md 2>/dev/null; then
    HUMAN_GATE="PENDING — verify session-state.md before merging"
  fi
fi

{
  echo "# pre-compact-state — generated before compaction (gitignored .claude/*.tmp)"
  echo "ts=${TS}"
  echo "branch=${BRANCH}"
  echo "head=${HEAD}"
  echo "wt=${WT}"
  echo "phase=${PHASE}"
  echo "obj=${OBJ}"
  echo "next=${NEXT}"
  echo "risks=${RISKS}"
  echo "human_gate=${HUMAN_GATE}"
} > .claude/pre-compact-state.tmp

exit 0
