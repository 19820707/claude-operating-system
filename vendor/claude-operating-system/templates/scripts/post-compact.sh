#!/usr/bin/env bash
# OS post-compact — re-injects compact session summary after context compaction.
# Uses .claude/pre-compact-state.tmp to give Claude real continuity context.
# Invariant: output is injected by Claude Code as context. H10: LF-only. Exit 0.
set -euo pipefail

BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
HEAD=$(git log -1 --format="%h %s" 2>/dev/null || echo unknown)
WT=$(git status --short 2>/dev/null | wc -l | tr -d " ")

echo "[OS-POST-COMPACT] WARNING: CONTEXT WAS COMPACTED"
echo "  Prior conversation is gone. Snapshot below is from pre-compact hook."
echo "  Verify against .claude/session-state.md before continuing any work."
echo ""

if [ -f ".claude/pre-compact-state.tmp" ]; then
  PC_TS=$(grep "^ts="         .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_BR=$(grep "^branch="     .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_HD=$(grep "^head="       .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_WT=$(grep "^wt="         .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_PH=$(grep "^phase="      .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_OB=$(grep "^obj="        .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_NX=$(grep "^next="       .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_RK=$(grep "^risks="      .claude/pre-compact-state.tmp | cut -d= -f2-)
  PC_GT=$(grep "^human_gate=" .claude/pre-compact-state.tmp | cut -d= -f2-)

  echo "  ── Pre-compact snapshot (${PC_TS}) ───────────────────────"
  echo "  branch  : ${PC_BR}"
  echo "  head    : ${PC_HD}"
  echo "  wt      : ${PC_WT} files at compaction"
  echo "  phase   : ${PC_PH}"
  echo "  obj     : ${PC_OB}"
  echo "  next    : ${PC_NX}"
  if [ -n "${PC_RK}" ] && [ "${PC_RK}" != "none" ]; then
    echo "  risks   : ${PC_RK}"
  fi
  if [ "${PC_GT}" != "none" ]; then
    echo "  GATE    : ${PC_GT}"
  fi
  echo "  ──────────────────────────────────────────────────────────"
else
  echo "  [no pre-compact snapshot — first compaction or hook not run]"
  echo "  branch : ${BRANCH} | head : ${HEAD} | wt : ${WT} files"
fi

echo ""
echo "  Mandatory re-read (skim — token-economy.md):"
echo "    1. .claude/session-state.md    (deep — verify branch + phase + risks)"
echo "    2. .claude/learning-log.md     (Grep by keyword, not full read)"
echo "    3. .claude/heuristics/operational.md  (skim active H<n>)"
echo ""
echo "  Route if active:"
echo "    SEV-1/2 incident    -> /incident-triage"
echo "    release hypercare   -> /release-readiness"
echo "    critical surface    -> Critical mode + Opus mandatory"
echo "    phase closing       -> /phase-close"

exit 0
