#!/usr/bin/env bash
# OS session-end — captures WT state to .claude/wt-snapshot.tmp for next session pre-flight.
# H10: LF-only. Exit 0 always (non-blocking).
set -euo pipefail

SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)

BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
HEAD=$(git log -1 --format="%h %s" 2>/dev/null || echo unknown)
WT_OUT=$(git status --short 2>/dev/null || echo "")
WT_COUNT=$(echo "${WT_OUT}" | grep -c . 2>/dev/null || echo 0)
TS=$(date -u +"%Y-%m-%dT%H:%MZ" 2>/dev/null || echo unknown)

{
  echo "# wt-snapshot — written by session-end hook (gitignored .claude/*.tmp)"
  echo "ts=${TS}"
  echo "branch=${BRANCH}"
  echo "head=${HEAD}"
  echo "wt_count=${WT_COUNT}"
  if [ "${WT_COUNT}" -gt 0 ]; then
    echo "wt_files<<END"
    echo "${WT_OUT}"
    echo "END"
  fi
} > .claude/wt-snapshot.tmp

if [ -f "${SCRIPTS_DIR}/session-index-build.sh" ]; then
  bash "${SCRIPTS_DIR}/session-index-build.sh" || true
fi

exit 0
